module Byraft
  class Node
    module State
      # persistent
      attr_accessor :current_term, :voted_for, :log
      # volatile
      attr_accessor :commit_index, :last_applied, :next_index, :match_index

      def commit!
        if @commit_index > @last_applied
          ((@last_applied + 1)..@commit_index).each { |i| execute_command(@log[i].command) }
          @last_applied = commit_index
        end
      end

      def execute_command(command)
        raise NotImplementedError
      end
    end
  end
end
