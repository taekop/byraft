require 'timeout'

require 'byraft/grpc/byraft_services_pb'
require 'byraft/node/election_timer'
require 'byraft/node/entry'
require 'byraft/node/logger'
require 'byraft/node/role'
require 'byraft/node/state'

module Byraft
  class Node
    include GRPC::Byraft
    include ElectionTimer
    include Logger
    include Role
    include State

    # config
    attr_reader :id, :nodes, :other_ids, :clients, :update_period, :verbose

    def initialize(id, nodes, election_timeout: (1..2), update_period: 0.1, verbose: false)
      # config
      @id = id
      @nodes = nodes
      @other_ids = nodes.except(id).keys
      @clients = nodes.except(id).transform_values { |address| GRPC::Stub.new(address, :this_channel_is_insecure) }
      @update_period = update_period
      @verbose = verbose

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

    def update
      log_info("update")
      if (follower? || candidate?) && election_timeout?
        change_role(:candidate)
      elsif leader?
        request_append_entries(true)
      end
    end

    def append_entries(msg, _call)
      log_info("get append entries request #{msg}")
      reset_election_timer!
      change_role(:follower) if (candidate? || leader?) && msg.term >= @current_term
      if msg.term < @current_term || @log[msg.prev_log_index]&.term != msg.prev_log_term
        # respond with failure
        GRPC::AppendEntriesResponse.new(term: @current_term, success: false)
      else
        # update term
        @current_term = msg.term

        # delete conflict
        first_conflict_index = msg.entries.find { |entry| !@log[entry.index].nil? && @log[entry.index].term != entry.term }&.index
        unless first_conflict_index.nil?
          @log.slice!(first_conflict_index..-1)
        end

        # append log
        msg.entries.each do |entry|
          @log[entry.index] = Entry.new(entry.index, entry.term, entry.command)
        end

        # set commit index
        @commit_index = [msg.leader_commit, msg.entries.last.index].min if msg.leader_commit > @commit_index && !msg.entries.empty?
        commit!

        # respond with success
        GRPC::AppendEntriesResponse.new(term: @current_term, success: true)
      end
    end

    def request_vote(msg, _call)
      log_info("get vote request #{msg}")
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

    def change_role(role)
      log_info("change role to #{role}")
      case role
      when :follower
        follower!
      when :candidate
        candidate!
        run_for_leader
      when :leader
        leader!
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
        log_info("run for leader in term #{current_term}")
        vote_cnt = 1
        mutex_vote_cnt = Mutex.new
        detect_other_leader = false
        msg = GRPC::RequestVoteRequest.new(term: @current_term, candidate_id: @id, last_log_index: @log.last.index, last_log_term: @log.last.term)
        threads = @clients.map do |follower_id, client|
          Thread.new do
            ::Timeout::timeout(until_election_timeout) do
              res = client.request_vote(msg)
              log_info("get vote response from Node##{follower_id} #{res}")
              mutex_vote_cnt.synchronize { vote_cnt += 1 } if res.vote_granted
              detect_other_leader = true if res.term > @current_term
            rescue ::GRPC::Unavailable
              retry
            end
          rescue ::Timeout::Error
          end
        end
        threads.each(&:join)
        majority = @nodes.size / 2 + 1
        log_info("Node##{id} get #{vote_cnt} votes")
        if detect_other_leader
          change_role(:follower)
        elsif vote_cnt >= majority
          change_role(:leader)
        end
      end
    end

    def request_append_entries(heartbeat = false)
      detect_other_leader = false
      threads = @other_ids.map do |follower_id|
        client = @clients[follower_id]
        Thread.new do
          retry_cnt = 0
          # loop until follower becomes consistent
          loop do
            next_index = @next_index[follower_id]
            prev_log_index = next_index - 1
            prev_log_term = @log[prev_log_index].term
            entries = heartbeat ? [] : @log[next_index..].map { |entry| GRPC::Entry.new(index: entry.index, term: entry.term, command: entry.command) }
            msg = GRPC::AppendEntriesRequest.new(term: @current_term, leader_id: @id, prev_log_index: prev_log_index, prev_log_term: prev_log_term, entries: entries, leader_commit: @commit_index)
            res = client.append_entries(msg)
            log_info("get append entries response from Node##{follower_id} #{res}")
            if res.success
              unless entries.empty?
                @match_index[follower_id] = entries.last.index
                @next_index[follower_id] = @match_index[follower_id] + 1
              end
              break
            elsif res.term > @current_term
              detect_other_leader = true
              break
            else
              @next_index[follower_id] -= 1
            end
          rescue ::GRPC::Unavailable, ::GRPC::Cancelled
            retry_cnt += 1
            break if retry_cnt >= 3
          end
        end
      end
      threads.each(&:join)
      if detect_other_leader
        change_role(:follower)
      end
    end

    private

    def mutex_current_term
      @mutex_current_term ||= Mutex.new
    end
  end
end
