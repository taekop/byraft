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
      @id = id.to_s
      @nodes = nodes
      @other_ids = nodes.except(id).keys
      @clients = nodes.except(id).transform_values { |address| GRPC::Stub.new(address, :this_channel_is_insecure) }
      @heartbeat_period = heartbeat_period

      # default value for optional config
      @logger = Logger.new(STDOUT)
      @executor = { node_id: @id }.tap do |obj|
        def obj.call(command)
          File.write("log/log-node-#{self[:node_id]}.txt", command + "\n", mode: 'a')
        end
      end

      # election timer
      @election_timeout = election_timeout

      # role
      @role = Role::FOLLOWER

      # state
      @current_term = 0
      @voted_for = nil
      @log = [Entry.new(0, 0, nil)]
      @commit_index = 0
      @last_applied = 0
    end

    def start(address)
      reset_election_timer!(start: true)
      @server_thread = Thread.new do
        self.print_log("Running...")
        s = ::GRPC::RpcServer.new
        s.add_http2_port(address, :this_port_is_insecure)
        s.handle(self)
        s.run_till_terminated_or_interrupted(['INT', 'TERM'])
      end
      @heartbeat_thread = Thread.new do
        loop do
          sleep(self.heartbeat_period)
          self.heartbeat
        end
      end
    end

    def join
      @server_thread.join
      @heartbeat_thread.kill
    end

    def stop
      @server_thread.kill
      @heartbeat_thread.kill
    end

    # called by periodic timer
    def heartbeat
      print_log("Heartbeat", level: :debug)
      if (follower? || candidate?) && election_timeout?
        change_role(:candidate)
      elsif leader?
        request_append_entries
      end
    end

    # called by leader
    def append_entries(msg, _call)
      print_log("gRPC Request: AppendEntries #{msg}", level: :debug)
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
      print_log("gRPC Request: RequestVote #{msg}", level: :debug)
      reset_election_timer!
      mutex_current_term.synchronize do
        valid_term = msg.term >= @current_term
        valid_vote = msg.term != @current_term || @voted_for.nil? || @voted_for == msg.candidate_id
        valid_log = msg.last_log_index >= @log.last.index && msg.last_log_term >= @log.last.term
        if valid_term && valid_vote && valid_log
          @current_term = msg.term
          @voted_for = msg.candidate_id
          print_log("Vote Node#{msg.candidate_id} in term #{msg.term}")
          GRPC::RequestVoteResponse.new(term: @current_term, vote_granted: true)
        else
          print_log("Refuse to vote Node##{msg.candidate_id} in term #{msg.term}")
          GRPC::RequestVoteResponse.new(term: @current_term, vote_granted: false)
        end
      end
    end

    # called by external client
    def append_log(msg, _call)
      print_log("gRPC Request: AppendLog #{msg}", level: :debug)
      if leader?
        @log.append(Entry.new(@log.size, @current_term, msg.command))
        request_append_entries
        GRPC::AppendLogResponse.new(success: true)
      else
        GRPC::AppendLogResponse.new(success: false, leader_id: @leader_id, leader_address: @nodes[@leader_id])
      end
    end

    def change_role(role)
      print_log("Change role to #{role}")
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
        request_append_entries
      end
    end

    def run_for_leader
      return if mutex_current_term.locked?
      mutex_current_term.synchronize do
        reset_election_timer!
        @current_term += 1
        @voted_for = @id
        print_log("Run for leader in term #{@current_term}")
        vote_cnt = 1
        mutex_vote_cnt = Mutex.new
        mutex_max_term = Mutex.new
        max_term = 0
        msg = GRPC::RequestVoteRequest.new(term: @current_term, candidate_id: @id, last_log_index: @log.last.index, last_log_term: @log.last.term)
        threads = @clients.map do |follower_id, client|
          Thread.new do
            ::Timeout::timeout(until_next_election) do
              res = client.request_vote(msg)
              print_log("Get RequestVoteResponse from Node##{follower_id}: #{res}", level: :debug)
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
        print_log("Get #{vote_cnt} votes in term #{@current_term}", level: :debug)
        if detect_other_leader
          print_log("Detect other leader during election", level: :debug)
          @current_term = max_term
          change_role(:follower)
        elsif vote_cnt >= majority
          change_role(:leader)
        end
      end
    end

    def request_append_entries
      print_log("Send request: AppendEntries to other nodes", level: :debug)
      detect_other_leader = false
      threads = @other_ids.map do |follower_id|
        client = @clients[follower_id]
        Thread.new do
          ::Timeout.timeout(until_next_election) do
            next_index = @next_index[follower_id]
            prev_log_index = next_index - 1
            prev_log_term = @log[prev_log_index].term
            entries = @log[next_index..].map { |entry| GRPC::Entry.new(index: entry.index, term: entry.term, command: entry.command) }
            msg = GRPC::AppendEntriesRequest.new(term: @current_term, leader_id: @id, prev_log_index: prev_log_index, prev_log_term: prev_log_term, entries: entries, leader_commit: @commit_index)
            res = client.append_entries(msg)
            print_log("Get AppendEntriesResponse from Node##{follower_id}: #{res}", level: :debug)
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
            print_log("Failed to get AppendEntriesResponse from Node##{follower_id}", level: :debug)
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
        mutex_last_applied.synchronize do
          commands = @log[(@last_applied + 1)..@commit_index].map(&:command)
          print_log("Commit from #{@last_applied + 1} to #{@commit_index}: #{commands}")
          commands.each { |command| @executor.call(command) }
          @last_applied = @commit_index
        end
      end
    end

    def colorize
      @colors ||= { follower: ["\e[37m", "\e[0m"], candidate: ["\e[33m", "\e[0m"], leader: ["\e[36m", "\e[0m"] }
      msg = "Node##{@id} [#{@current_term}]"
      @colors[current_role][0] + msg + @colors[current_role][1]
    end

    private

    def print_log(msg, level: :info)
      @logger.send(level, self.colorize) { msg }
    end

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
