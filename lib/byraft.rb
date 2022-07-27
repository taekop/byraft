require 'byraft/node'

module Byraft
  # @param id [String]
  # @param nodes [Hash] id as key, and address as value
  # @option election_timeout [Range] Randomize election timeout in range
  # @option heartbeat_period [Float] Heartbeat period
  # @option logger_level [Integer] DEBUG, INFO, WARN, ERROR, FATAL, UNKNOWN
  #
  # @example
  #
  # Byraft.start('1', 50051, { 1 => '0.0.0.0:50051', 2 => '0.0.0.0:50052', 3 => '0.0.0.0:50053' })
  def self.start(id, port, nodes, **opts)
    logger_level = opts.delete(:logger_level)
    node = Node.new(id, nodes, **opts)
    node.logger.level = logger_level || 0
    address = "localhost:#{port}"
    @server_thread = Thread.new do
      node.logger.info(node.colorize) { "Running..." }
      s = ::GRPC::RpcServer.new
      s.add_http2_port(address, :this_port_is_insecure)
      s.handle(node)
      s.run_till_terminated_or_interrupted(['INT', 'TERM'])
    end
    @ping_thread = Thread.new do
      loop do
        sleep(node.heartbeat_period)
        node.heartbeat
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
