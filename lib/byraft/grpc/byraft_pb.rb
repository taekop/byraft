# Generated by the protocol buffer compiler.  DO NOT EDIT!
# source: raft.proto

require 'google/protobuf'

Google::Protobuf::DescriptorPool.generated_pool.build do
  add_file("raft.proto", :syntax => :proto3) do
    add_message "raft.Entry" do
      proto3_optional :index, :int32, 1
      proto3_optional :term, :int32, 2
      proto3_optional :command, :string, 3
    end
    add_message "raft.AppendEntriesRequest" do
      proto3_optional :term, :int32, 1
      proto3_optional :leader_id, :string, 2
      proto3_optional :prev_log_index, :int32, 3
      proto3_optional :prev_log_term, :int32, 4
      repeated :entries, :message, 5, "raft.Entry"
      proto3_optional :leader_commit, :int32, 6
    end
    add_message "raft.AppendEntriesResponse" do
      proto3_optional :term, :int32, 1
      proto3_optional :success, :bool, 2
    end
    add_message "raft.RequestVoteRequest" do
      proto3_optional :term, :int32, 1
      proto3_optional :candidate_id, :string, 2
      proto3_optional :last_log_index, :int32, 3
      proto3_optional :last_log_term, :int32, 4
    end
    add_message "raft.RequestVoteResponse" do
      proto3_optional :term, :int32, 1
      proto3_optional :vote_granted, :bool, 2
    end
    add_message "raft.AppendLogRequest" do
      proto3_optional :command, :string, 1
    end
    add_message "raft.AppendLogResponse" do
      proto3_optional :success, :bool, 1
      proto3_optional :leader_id, :string, 2
      proto3_optional :leader_address, :string, 3
    end
  end
end

module Byraft
  module GRPC
    Entry = ::Google::Protobuf::DescriptorPool.generated_pool.lookup("raft.Entry").msgclass
    AppendEntriesRequest = ::Google::Protobuf::DescriptorPool.generated_pool.lookup("raft.AppendEntriesRequest").msgclass
    AppendEntriesResponse = ::Google::Protobuf::DescriptorPool.generated_pool.lookup("raft.AppendEntriesResponse").msgclass
    RequestVoteRequest = ::Google::Protobuf::DescriptorPool.generated_pool.lookup("raft.RequestVoteRequest").msgclass
    RequestVoteResponse = ::Google::Protobuf::DescriptorPool.generated_pool.lookup("raft.RequestVoteResponse").msgclass
    AppendLogRequest = ::Google::Protobuf::DescriptorPool.generated_pool.lookup("raft.AppendLogRequest").msgclass
    AppendLogResponse = ::Google::Protobuf::DescriptorPool.generated_pool.lookup("raft.AppendLogResponse").msgclass
  end
end
