require 'byraft/node'

module Byraft
  # @param id [String]
  # @param nodes [Hash]: id as key, and address as value
  #
  # @example
  #
  # Byraft.start('1', 50051, { 1 => '0.0.0.0:50051', 2 => '0.0.0.0:50052', 3 => '0.0.0.0:50053' })
  def self.start(id, port, nodes, **opts)
    node = Node.new(id, nodes, **opts)
    address = "localhost:#{port}"
    @server_thread = Thread.new do
      puts "Node##{id} running..." if opts[:verbose]
      s = ::GRPC::RpcServer.new
      s.add_http2_port(address, :this_port_is_insecure)
      s.handle(node)
      s.run_till_terminated_or_interrupted(['INT', 'TERM'])
    end
    @ping_thread = Thread.new do
      loop do
        sleep(node.update_period)
        node.update
      end
    end
  end

  def self.join
    @server_thread.join
    @ping_thread.kill
  end

  def self.stop
    @server_thread.kill
    @ping_thread.kill
  end
end
