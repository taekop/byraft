require 'spec_helper'

RSpec.describe Byraft do
  it 'start & join' do
    Byraft.start('1', 50051, { 1 => '0.0.0.0:50051', 2 => '0.0.0.0:50052', 3 => '0.0.0.0:50053' }, logger_level: 2)
    # interrupt current thread
    Thread.new { sleep(1); Process.kill('INT', 0) }
    Byraft.join
  end

  it 'start & stop' do
    Byraft.start('1', 50051, { 1 => '0.0.0.0:50051', 2 => '0.0.0.0:50052', 3 => '0.0.0.0:50053' }, logger_level: 2)
    Byraft.stop
  end
end
