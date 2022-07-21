require 'spec_helper'

RSpec.describe Byraft::Node::ElectionTimer do
  let(:klass) { Class.new { include Byraft::Node::ElectionTimer } }
  let(:obj) { klass.new.tap { |obj| obj.election_timeout = 60..60 } }

  it '> election timeout?' do
    Timecop.freeze(Time.now)
    obj.reset_election_timer!
    expect(obj.election_timeout?).to be_falsey
    Timecop.return
    Timecop.freeze(Time.now + 60)
    expect(obj.election_timeout?).to be_truthy
    Timecop.return
  end

  it '> until election timeout' do
    Timecop.freeze(Time.now)
    obj.reset_election_timer!
    expect(obj.until_election_timeout).to eq 60
    Timecop.return
    Timecop.freeze(Time.now + 60)
    expect(obj.election_timeout?).to be_truthy
    Timecop.return
  end
end
