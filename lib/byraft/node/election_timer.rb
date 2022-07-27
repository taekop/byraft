module Byraft
  class Node
    module ElectionTimer
      attr_accessor :heartbeat_time, :election_timeout, :next_election_timeout

      def reset_election_timer!
        @heartbeat_time = Time.now.to_f
        @next_election_timeout = rand(@election_timeout)
      end

      def election_timeout?
        Time.now.to_f > @heartbeat_time + @next_election_timeout
      end

      # half timeout to prevent leader switching due to delayed response
      def until_next_election
        (@heartbeat_time + @next_election_timeout / 2 - Time.now.to_f).clamp(0.1..)
      end
    end
  end
end
