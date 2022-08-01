dir = File.expand_path(File.dirname(__FILE__))
$LOAD_PATH.unshift(dir) unless $LOAD_PATH.include?(dir)
require 'byraft/node'

module Byraft
  # @param id [String]
  # @param port [Integer]
  # @param nodes [Hash] id as key, and address as value
  # @option election_timeout [Range] Randomize election timeout in range
  # @option heartbeat_period [Float] Heartbeat period
  # @option logger_level [Integer] DEBUG, INFO, WARN, ERROR, FATAL, UNKNOWN
  #
  # @example
  #
  # Byraft.start('1', 50051, { 1 => '0.0.0.0:50051', 2 => '0.0.0.0:50052', 3 => '0.0.0.0:50053' })
  def self.start(id, port, nodes, **opts)
    address = "localhost:#{port}"
    logger_level = opts.delete(:logger_level)
    @node = Node.new(id, nodes, **opts)
    @node.logger.level = logger_level || 0
    @node.start(address)
  end

  def self.join
    @node.join
  end

  def self.stop
    @node.stop
  end
end
