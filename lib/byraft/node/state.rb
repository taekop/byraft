module Byraft
  class Node
    module State
      # persistent
      attr_accessor :current_term, :voted_for, :log
      # volatile
      attr_accessor :commit_index, :last_applied, :next_index, :match_index
      # extra
      attr_accessor :leader_id
    end
  end
end
