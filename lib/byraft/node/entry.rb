module Byraft
  class Node
    Entry = Struct.new(:index, :term, :command)
  end
end
