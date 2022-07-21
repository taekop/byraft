module Byraft
  class Node
    module Role
      FOLLOWER = 0
      CANDIDATE = 1
      LEADER = 2

      attr_accessor :role

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
