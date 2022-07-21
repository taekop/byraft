class String
  def black;          "\e[30m#{self}\e[0m" end
  def red;            "\e[31m#{self}\e[0m" end
  def green;          "\e[32m#{self}\e[0m" end
  def yellow;         "\e[33m#{self}\e[0m" end
  def blue;           "\e[34m#{self}\e[0m" end
  def magenta;        "\e[35m#{self}\e[0m" end
  def cyan;           "\e[36m#{self}\e[0m" end
  def gray;           "\e[37m#{self}\e[0m" end
end

module Byraft
  class Node
    module Logger
      def log_info(msg)
        puts _node_info + "\t" + msg if verbose
      end

      def _node_info
        msg = "Node##{id}"
        if follower?
          msg.gray
        elsif candidate?
          msg.yellow
        else
          msg.cyan
        end
      end
    end
  end
end
