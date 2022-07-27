require 'grpc'

require 'byraft/grpc/byraft_pb'

module Byraft
  module GRPC
    # Interface exported by the server.
    module Byraft
      def self.included klass
        klass.class_eval do
          include ::GRPC::GenericService

          klass.marshal_class_method = :encode
          klass.unmarshal_class_method = :decode
          klass.service_name = 'byraft.RaftNode'

          klass.rpc :AppendEntries, AppendEntriesRequest, AppendEntriesResponse
          klass.rpc :RequestVote, RequestVoteRequest, RequestVoteResponse
          klass.rpc :AppendLog, AppendLogRequest, AppendLogResponse
        end
      end
    end

    Stub = Class.new.include(Byraft).rpc_stub_class
  end
end
