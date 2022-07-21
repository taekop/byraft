require 'spec_helper'

RSpec.describe Byraft::Node::Role do
  let(:klass) { Class.new { include Byraft::Node::Role } }
  let(:obj) { klass.new }

  it '> follower?' do
    obj.role = Byraft::Node::Role::FOLLOWER
    expect(obj.follower?).to be_truthy
  end

  it '> follower!' do
    obj.follower!
    expect(obj.follower?).to be_truthy
  end

  it '> candidate?' do
    obj.role = Byraft::Node::Role::CANDIDATE
    expect(obj.candidate?).to be_truthy
  end

  it '> candidate!' do
    obj.candidate!
    expect(obj.candidate?).to be_truthy
  end

  it '> leader?' do
    obj.role = Byraft::Node::Role::LEADER
    expect(obj.leader?).to be_truthy
  end

  it '> leader!' do
    obj.leader!
    expect(obj.leader?).to be_truthy
  end
end
