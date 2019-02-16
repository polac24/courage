module Courage

  module Mutation


    class SILDependencies
      def initialize(object)
        if object.nil?
          @functions = []
        else
          @functions = object.map{|x|
            SILDependency.new(x)
          }
        end
      end
      def print_after_function(output, already_defined_symbols)
        @functions.each {|x|
          x.print_after_function(output, already_defined_symbols)
        }
      end
    end
    class SILDependency
      def initialize(object)
        file = object["file"]
        @symbols = Parser::SILParser.new(File.join(__dir__, file)).symbols
      end
      def print_after_function(output, already_defined_symbols)
        @symbols.each{|symbol|
          symbol.print(output) unless already_defined_symbols.include? symbol.definition.name
        }
      end
    end
  end
end