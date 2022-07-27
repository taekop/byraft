module Byraft
  class Node
    module Role
      FOLLOWER = 0
      CANDIDATE = 1
      LEADER = 2

      attr_accessor :role

      def current_role
        case @role
        when FOLLOWER
          :follower
        when CANDIDATE
          :candidate
        when LEADER
          :leader
        else
          raise "Invalid value for role: #{@role} must be in #{[FOLLOWER, CANDIDATE, LEADER]}"
        end
      end

      def leader!
        @role = LEADER
      end

      def leader?
        @role == LEADER
      end

      def candidate!
        @role = CANDIDATE
      end

      def candidate?
        @role == CANDIDATE
      end

      def follower!
        @role = FOLLOWER
      end

      def follower?
        @role == FOLLOWER
      end
    end
  end
end
