require 'google/protobuf'

Google::Protobuf::DescriptorPool.generated_pool.build do
  add_message "byraft.Entry" do
    optional :index, :int32, 1
    optional :term, :int32, 2
    optional :command, :string, 3
  end

  add_message "byraft.AppendEntriesRequest" do
    optional :term, :int32, 1
    optional :leader_id, :string, 2
    optional :prev_log_index, :int32, 3
    optional :prev_log_term, :int32, 4
    repeated :entries, :message, 5, "byraft.Entry"
    optional :leader_commit, :int32, 6
  end

  add_message "byraft.AppendEntriesResponse" do
    optional :term, :int32, 1
    optional :success, :bool, 2
  end

  add_message "byraft.RequestVoteRequest" do
    optional :term, :int32, 1
    optional :candidate_id, :string, 2
    optional :last_log_index, :int32, 3
    optional :last_log_term, :int32, 4
  end

  add_message "byraft.RequestVoteResponse" do
    optional :term, :int32, 1
    optional :vote_granted, :bool, 2
  end
end

module Byraft
  module GRPC
    Entry = Google::Protobuf::DescriptorPool.generated_pool.lookup("byraft.Entry").msgclass
    AppendEntriesRequest = Google::Protobuf::DescriptorPool.generated_pool.lookup("byraft.AppendEntriesRequest").msgclass
    AppendEntriesResponse = Google::Protobuf::DescriptorPool.generated_pool.lookup("byraft.AppendEntriesResponse").msgclass
    RequestVoteRequest = Google::Protobuf::DescriptorPool.generated_pool.lookup("byraft.RequestVoteRequest").msgclass
    RequestVoteResponse = Google::Protobuf::DescriptorPool.generated_pool.lookup("byraft.RequestVoteResponse").msgclass
  end
end
