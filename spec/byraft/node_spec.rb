require 'spec_helper'

RSpec.describe Byraft::Node do
  let(:node) { Byraft::Node.new('1', { '1' => '0.0.0.0:50051', '2' => '0.0.0.0:50052', '3' => '0.0.0.0:50053' }) }

  describe 'append entries' do
    it '> reset election timer' do
      t = Time.local(2022)
      Timecop.freeze(t)
      msg = Byraft::GRPC::AppendEntriesRequest.new(term: 1, leader_id: '2', prev_log_index: 0, prev_log_term: 0, entries: [], leader_commit: 1)
      node.append_entries(msg, nil)
      expect(node.heartbeat_time).to eq t.to_f
      Timecop.return
    end

    it '> return false and current term when current term is bigger than msg' do
      node.current_term = 2
      msg = Byraft::GRPC::AppendEntriesRequest.new(term: 1, leader_id: '2', prev_log_index: 0, prev_log_term: 0, entries: [], leader_commit: 1)
      res = node.append_entries(msg, nil)
      expect(res.term).to eq 2
      expect(res.success).to be_falsey
    end

    it '> return false and current term when prev log is inconsistent' do
      msg = Byraft::GRPC::AppendEntriesRequest.new(term: 1, leader_id: '2', prev_log_index: 0, prev_log_term: 1, entries: [], leader_commit: 1)
      res = node.append_entries(msg, nil)
      expect(res.term).to eq 0
      expect(res.success).to be_falsey

      msg = Byraft::GRPC::AppendEntriesRequest.new(term: 1, leader_id: '2', prev_log_index: 1, prev_log_term: 0, entries: [], leader_commit: 1)
      res = node.append_entries(msg, nil)
      expect(res.term).to eq 0
      expect(res.success).to be_falsey
    end

    it '> return true, update term, resolve conflict, and apply commit when prev log is consistent' do
      node.current_term = 1
      node.log.append(Byraft::Node::Entry.new(1, 1, 'INCONSISTENT'))
      msg = Byraft::GRPC::AppendEntriesRequest.new(term: 2, leader_id: '2', prev_log_index: 0, prev_log_term: 0, entries: [Byraft::GRPC::Entry.new(index: 1, term: 2, command: 'CONSISTENT')], leader_commit: 1)
      expect(node).to receive(:execute_command).with('CONSISTENT')
      res = node.append_entries(msg, nil)
      expect(res.term).to eq 2
      expect(res.success).to be_truthy
      expect(node.current_term).to eq 2
      expect(node.log).to eq [Byraft::Node::Entry.new(0, 0, nil), Byraft::Node::Entry.new(1, 2, 'CONSISTENT')]
    end

    context 'candidate' do
      before(:each) do
        node.candidate!
      end

      it '> become follower when msg term is not smaller than current term' do
        msg = Byraft::GRPC::AppendEntriesRequest.new(term: 1, leader_id: '2', prev_log_index: 0, prev_log_term: 0, entries: [], leader_commit: 1)
        expect(node.candidate?).to be_truthy
        node.append_entries(msg, nil)
        expect(node.follower?).to be_truthy
      end
    end

    context 'leader' do
      before(:each) do
        node.leader!
      end

      it '> become follower when msg term is not smaller than current term' do
        msg = Byraft::GRPC::AppendEntriesRequest.new(term: 1, leader_id: '2', prev_log_index: 0, prev_log_term: 0, entries: [], leader_commit: 1)
        expect(node.leader?).to be_truthy
        node.append_entries(msg, nil)
        expect(node.follower?).to be_truthy
      end
    end
  end

  describe 'request vote' do
    it '> reset election timer' do
      t = Time.local(2022)
      Timecop.freeze(t)
      msg = Byraft::GRPC::RequestVoteRequest.new(term: 1, candidate_id: '2', last_log_index: 0, last_log_term: 0)
      node.request_vote(msg, nil)
      expect(node.heartbeat_time).to eq t.to_f
      Timecop.return
    end

    it '> return false when msg term is smaller than current term' do
      node.current_term = 2
      msg = Byraft::GRPC::RequestVoteRequest.new(term: 1, candidate_id: '2', last_log_index: 0, last_log_term: 0)
      res = node.request_vote(msg, nil)
      expect(res.vote_granted).to be_falsey
    end

    it '> return false when vote is already granted to other candidate' do
      node.current_term = 1
      node.voted_for = 3
      msg = Byraft::GRPC::RequestVoteRequest.new(term: 1, candidate_id: '2', last_log_index: 0, last_log_term: 0)
      res = node.request_vote(msg, nil)
      expect(res.term).to eq 1
      expect(res.vote_granted).to be_falsey
    end

    it '> return false when candidate log is not up-to-date' do
      node.log.append(Byraft::Node::Entry.new(1, 1, nil))
      msg = Byraft::GRPC::RequestVoteRequest.new(term: 1, candidate_id: '2', last_log_index: 0, last_log_term: 0)
      res = node.request_vote(msg, nil)
      expect(res.term).to eq 0
      expect(res.vote_granted).to be_falsey
    end

    it '> return true' do
      msg = Byraft::GRPC::RequestVoteRequest.new(term: 1, candidate_id: '2', last_log_index: 0, last_log_term: 0)
      res = node.request_vote(msg, nil)
      expect(res.term).to eq 1
      expect(res.vote_granted).to be_truthy
    end
  end

  describe 'update' do
    context 'follower' do
      before(:each) do
        node.follower!
      end

      it '> become candidate when election timeout' do
        allow(node).to receive(:election_timeout?).and_return(true)
        expect(node).to receive(:change_role).with(:candidate)
        node.update
      end
    end

    context 'candidate' do
      before(:each) do
        node.candidate!
      end

      it '> become candidate when election timeout' do
        allow(node).to receive(:election_timeout?).and_return(true)
        expect(node).to receive(:change_role).with(:candidate)
        node.update
      end
    end

    context 'leader' do
      before(:each) do
        node.leader!
      end

      it '> send heartbeat messages' do
        expect(node).to receive(:request_append_entries).with(true)
        node.update
      end
    end
  end

  describe 'change_role' do
    it '> become follower' do
      node.change_role(:follower)
      expect(node.follower?).to be_truthy
    end

    it '> become candidate and run for leader' do
      expect(node).to receive(:run_for_leader)
      node.change_role(:candidate)
      expect(node.candidate?).to be_truthy
    end

    it '> become leader, initialize leader state, and send heartbeat messages' do
      expect(node).to receive(:request_append_entries).with(true)
      node.change_role(:leader)
      expect(node.leader?).to be_truthy
      expect(node.next_index).to eq({ '2' => 1, '3' => 1 })
      expect(node.match_index).to eq({ '2' => 0, '3' => 0 })
    end
  end

  describe 'run for leader' do
    def stub_request_vote(term, vote_granted)
      node.clients.values.each do |client|
        allow(client).to receive(:request_vote).and_return(Byraft::GRPC::RequestVoteResponse.new(term: term, vote_granted: vote_granted))
      end
    end

    it '> reset election timer' do
      stub_request_vote(0, true)
      t = Time.local(2022)
      Timecop.freeze(t)
      expect(node).to receive(:change_role).with(:leader)
      node.run_for_leader
      expect(node.heartbeat_time).to eq t.to_f
      Timecop.return
    end

    it '> update current_term and voted_for' do
      stub_request_vote(0, true)
      expect(node).to receive(:change_role).with(:leader)
      node.run_for_leader
      expect(node.current_term).to eq 1
      expect(node.voted_for).to eq '1'
    end

    it '> update current_term and voted_for' do
      stub_request_vote(0, true)
      expect(node).to receive(:change_role).with(:leader)
      node.run_for_leader
      expect(node.current_term).to eq 1
      expect(node.voted_for).to eq '1'
    end

    it '> retry when lose election' do
      stub_request_vote(1, false)
      allow(node).to receive(:run_for_leader).and_call_original
      allow(node).to receive(:run_for_leader).and_return(:SECOND_CALL)
      expect(node.run_for_leader).to eq :SECOND_CALL
    end

    it '> become follower when other leader detected' do
      stub_request_vote(2, false)
      expect(node).to receive(:change_role).with(:follower)
      node.run_for_leader
    end
  end

  describe 'request append entries' do
    before(:each) do
      node.leader!
      node.current_term = 1
      node.next_index = { '2' => 1, '3' => 1 }
      node.match_index = { '2' => 0, '3' => 0 }
    end

    def stub_append_entries(term, success)
      node.clients.values.each do |client|
        allow(client).to receive(:append_entries).and_return(Byraft::GRPC::AppendEntriesResponse.new(term: term, success: success))
      end
    end

    def multiple_stub_append_entries(term_successes)
      responses = term_successes.map { |term, success| Byraft::GRPC::AppendEntriesResponse.new(term: term, success: success) }
      node.clients.values.each do |client|
        allow(client).to receive(:append_entries).and_return(*responses)
      end
    end

    context 'heartbeat' do
      it '> send request to nodes' do
        stub_append_entries(0, true)
        node.clients.values.each do |client|
          expect(client).to receive(:append_entries)
        end
        node.request_append_entries(true)
      end

      it '> become follower when other leader detected' do
        stub_append_entries(2, false)
        node.clients.values.each do |client|
          expect(client).to receive(:append_entries)
        end
        node.request_append_entries(true)
        expect(node.follower?).to be_truthy
      end
    end

    context 'non-heartbeat' do
      before(:each) do
        node.log.append(Byraft::Node::Entry.new(1, 1, 'RUN COMMAND'))
        node.next_index = { '2' => 2, '3' => 2 }
      end

      it '> send request to nodes' do
        stub_append_entries(1, true)
        node.clients.values.each do |client|
          expect(client).to receive(:append_entries)
        end
        node.request_append_entries
      end

      it '> send request to nodes until consistent' do
        multiple_stub_append_entries([[1, false], [1, true]])
        node.clients.values.each do |client|
          expect(client).to receive(:append_entries).twice
        end
        node.request_append_entries
      end

      it '> become follower when other leader detected' do
        stub_append_entries(2, false)
        node.clients.values.each do |client|
          expect(client).to receive(:append_entries)
        end
        node.request_append_entries
        expect(node.follower?).to be_truthy
      end
    end
  end
end
