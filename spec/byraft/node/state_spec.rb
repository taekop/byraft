require 'spec_helper'

RSpec.describe Byraft::Node::State do
  let(:klass) { Class.new { include Byraft::Node::State } }
  let(:obj) { klass.new }

  it '> commit!' do
    obj.last_applied = 0
    obj.commit_index = 1
    obj.log = [Byraft::Node::Entry.new(0, 0, nil), Byraft::Node::Entry.new(1, 0, 'RUN COMMAND')]
    expect(obj).to receive(:execute_command).with('RUN COMMAND')
    obj.commit!
    expect(obj.last_applied).to eq 1
  end
end
