require 'logger'
require 'timeout'

require 'byraft/grpc/byraft_services_pb'
require 'byraft/node/election_timer'
require 'byraft/node/entry'
require 'byraft/node/role'
require 'byraft/node/state'

module Byraft
  class Node
    include GRPC::Byraft
    include ElectionTimer
    include Role
    include State

    # config
    attr_reader :id, :nodes, :other_ids, :clients, :heartbeat_period
    # optional config
    attr_accessor :logger, :executor

    def initialize(id, nodes, election_timeout: (1..2), heartbeat_period: 0.1)
      # config
      @id = id
      @nodes = nodes
      @other_ids = nodes.except(id).keys
      @clients = nodes.except(id).transform_values { |address| GRPC::Stub.new(address, :this_channel_is_insecure) }
      @heartbeat_period = heartbeat_period

      # default value for optional config
      @logger = Logger.new(STDOUT)
      @executor = { node_id: @id }.tap do |obj|
        def obj.call(command)
          File.write("log/log-node-#{self[:node_id]}.txt", command, mode: 'a')
        end
      end

      # election timer
      @election_timeout = election_timeout
      reset_election_timer!

      # role
      @role = Role::FOLLOWER

      # state
      @current_term = 0
      @voted_for = nil
      @log = [Entry.new(0, 0, nil)]
      @commit_index = 0
      @last_applied = 0
    end

    # called by periodic timer
    def heartbeat
      @logger.debug(self.colorize) { "Heartbeat" }
      if (follower? || candidate?) && election_timeout?
        change_role(:candidate)
      elsif leader?
        request_append_entries(true)
      end
    end

    # called by leader
    def append_entries(msg, _call)
      @logger.debug(self.colorize) { "gRPC Request: AppendEntries #{msg}" }
      reset_election_timer!
      change_role(:follower) if (candidate? || leader?) && msg.term >= @current_term
      if msg.term < @current_term || @log[msg.prev_log_index]&.term != msg.prev_log_term
        # respond with failure
        GRPC::AppendEntriesResponse.new(term: @current_term, success: false)
      else
        # update term, leader_id
        @current_term = msg.term
        @leader_id = msg.leader_id

        # delete conflict
        first_conflict_index = msg.entries.find { |entry| !@log[entry.index].nil? && @log[entry.index].term != entry.term }&.index
        unless first_conflict_index.nil?
          @log.slice!(first_conflict_index..-1)
        end

        # append log
        msg.entries.each do |entry|
          @log[entry.index] = Entry.new(entry.index, entry.term, entry.command)
        end

        # update commit index
        mutex_commit_index.synchronize do
          if msg.leader_commit > @commit_index
            @commit_index = [msg.leader_commit, @log.last.index].min
            commit!
          end
        end

        # respond with success
        GRPC::AppendEntriesResponse.new(term: @current_term, success: true)
      end
    end

    # called by candidate
    def request_vote(msg, _call)
      @logger.debug(self.colorize) { "gRPC Request: RequestVote #{msg}" }
      reset_election_timer!
      mutex_current_term.synchronize do
        valid_term = msg.term >= @current_term
        valid_vote = msg.term != @current_term || @voted_for.nil? || @voted_for == msg.candidate_id
        valid_log = msg.last_log_index >= @log.last.index && msg.last_log_term >= @log.last.term
        if valid_term && valid_vote && valid_log
          @current_term = msg.term
          @voted_for = msg.candidate_id
          GRPC::RequestVoteResponse.new(term: @current_term, vote_granted: true)
        else
          GRPC::RequestVoteResponse.new(term: @current_term, vote_granted: false)
        end
      end
    end

    # called by external client
    def append_log(msg, _call)
      @logger.debug(self.colorize) { "gRPC Request: AppendLog #{msg}" }
      if leader?
        @log.append(Entry.new(@log.size, @current_term, msg.command))
        request_append_entries
        GRPC::AppendLogResponse.new(success: true)
      else
        GRPC::AppendLogResponse.new(success: false, leader_id: @leader_id, leader_address: @nodes[@leader_id])
      end
    end

    def change_role(role)
      @logger.info(self.colorize) { "Change role to #{role}" }
      case role
      when :follower
        follower!
      when :candidate
        candidate!
        run_for_leader
      when :leader
        leader!
        @leader_id = @id
        @next_index = @other_ids.map { |id| [id, @log.last.index + 1] }.to_h
        @match_index = @other_ids.map { |id| [id, 0] }.to_h
        request_append_entries(true)
      end
    end

    def run_for_leader
      return if mutex_current_term.locked?
      mutex_current_term.synchronize do
        reset_election_timer!
        @current_term += 1
        @voted_for = @id
        @logger.info(self.colorize) { "Run for leader of term #{@current_term}" }
        vote_cnt = 1
        mutex_vote_cnt = Mutex.new
        mutex_max_term = Mutex.new
        max_term = 0
        msg = GRPC::RequestVoteRequest.new(term: @current_term, candidate_id: @id, last_log_index: @log.last.index, last_log_term: @log.last.term)
        threads = @clients.map do |follower_id, client|
          Thread.new do
            ::Timeout::timeout(until_next_election) do
              res = client.request_vote(msg)
              @logger.debug(self.colorize) { "Get RequestVoteResponse from Node##{follower_id}: #{res}" }
              mutex_vote_cnt.synchronize { vote_cnt += 1 } if res.vote_granted
              mutex_max_term.synchronize { max_term = res.term if max_term < res.term }
            rescue ::GRPC::Unavailable
              retry
            end
          rescue ::Timeout::Error
          end
        end
        threads.each(&:join)
        detect_other_leader = max_term > @current_term
        majority = @nodes.size / 2 + 1
        @logger.debug(self.colorize) { "Get #{vote_cnt} votes" }
        if detect_other_leader
          @logger.debug(self.colorize) { "Detect other leader during election" }
          @current_term = max_term
          change_role(:follower)
        elsif vote_cnt >= majority
          change_role(:leader)
        end
      end
    end

    def request_append_entries(heartbeat = false)
      @logger.debug(self.colorize) { "Send request: AppendEntries (heartbeat: #{heartbeat}) to other nodes" }
      detect_other_leader = false
      threads = @other_ids.map do |follower_id|
        client = @clients[follower_id]
        Thread.new do
          ::Timeout.timeout(until_next_election) do
            next_index = @next_index[follower_id]
            prev_log_index = next_index - 1
            prev_log_term = @log[prev_log_index].term
            entries = heartbeat ? [] : @log[next_index..].map { |entry| GRPC::Entry.new(index: entry.index, term: entry.term, command: entry.command) }
            msg = GRPC::AppendEntriesRequest.new(term: @current_term, leader_id: @id, prev_log_index: prev_log_index, prev_log_term: prev_log_term, entries: entries, leader_commit: @commit_index)
            res = client.append_entries(msg)
            @logger.debug(self.colorize) { "Get AppendEntriesResponse from Node##{follower_id}: #{res}" }
            if res.success
              unless entries.empty?
                @match_index[follower_id] = entries.last.index
                @next_index[follower_id] = @match_index[follower_id] + 1
              end
            elsif res.term > @current_term
              detect_other_leader = true
            else
              @next_index[follower_id] -= 1
            end
          rescue ::GRPC::Unavailable, ::GRPC::Cancelled
          end
        rescue ::Timeout::Error
        end
      end
      threads.each(&:join)
      if detect_other_leader
        change_role(:follower)
      else
        # update commit index
        majority = @nodes.size / 2 + 1
        majority_match_index = ([@log.last.index] + @match_index.values).sort[majority - 1]
        if majority_match_index > @commit_index && @log[majority_match_index].term == @current_term
          mutex_commit_index.synchronize { @commit_index = majority_match_index }
          commit!
        end
      end
    end

    def commit!
      if @commit_index > @last_applied
        @logger.info(self.colorize) { "Commit from #{@last_applied + 1} to #{@commit_index}" }
        mutex_last_applied.synchronize do
          ((@last_applied + 1)..@commit_index).each { |i| @executor.call(@log[i].command) }
          @last_applied = @commit_index
        end
      end
    end

    def colorize
      @colors ||= { follower: ["\e[37m", "\e[0m"], candidate: ["\e[33m", "\e[0m"], leader: ["\e[36m", "\e[0m"] }
      msg = "Node##{@id}"
      @colors[current_role][0] + msg + @colors[current_role][1]
    end

    private

    def mutex_current_term
      @mutex_current_term ||= Mutex.new
    end

    def mutex_commit_index
      @mutex_commit_index ||= Mutex.new
    end

    def mutex_last_applied
      @mutex_last_applied ||= Mutex.new
    end
  end
end
