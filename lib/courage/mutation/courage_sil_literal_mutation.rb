
module Courage

  module Mutation

    class SILLiteralMutation
      def initialize(object)
        @required = SILLiteralMutationRequired.new(object["required"])
        @actions = SILLiteralMutationActions.new(object["actions"])
        @name = object["name"]
      end
      def name
        @name
      end
      def count(function)
        @required.literals(function).count
      end
      def to_s
        @name
      end
      def isSupported(function, allowed_symbols)
        return false unless FunctionMutation.isSupported(function, allowed_symbols) 
        return count(function) > 0
      end
      def print_mutation(function, i, all_symbols, output)
        function.print_header(output)
        left_index = i
        building_blocks = function.building_blocks
        for block in building_blocks
          if left_index.nil?
            block.print_with_offset(output, 0, 0)
          else
            potential_literals = @required.literal_blocks(block, 0)
            if potential_literals.count <= left_index
              block.print(output)
              left_index -= potential_literals.count
            else
              literal_index = potential_literals[left_index]
              print_block_with_mutation(block, block.literals[literal_index], output)
              left_index = nil
            end
          end
        end
        function.print_end(output)
      end
      private def print_block_with_mutation(block, literal, output)
          block.print_head(output)
          literal_index = literal.line_number
          block.body[0...literal_index].each{|x| output.puts(x[:value])}
          @actions.print(output, literal)
          block.body[(literal_index)..-1].each{|x| output.puts(x[:value])}
      end
    end

    class SILLiteralMutationRequired
      def initialize(object)
        @type = object["type"]
      end
      def literal_blocks(building_block, offset)
        indexes = []
        all_literals = building_block.literals
        for i in 0...all_literals.count
          indexes.push(i+offset) if all_literals[i].type == @type
        end
        indexes
      end
      def literals(function)
        building_blocks = function.building_blocks
        indexes = []
        literals_offset = 0
        for i in 0...building_blocks.count
          indexes.concat(literal_blocks(building_blocks[i], literals_offset))
          literals_offset += building_blocks[i].literals.count
        end
        indexes
      end
    end
    class SILLiteralMutationActions
      def initialize(object)
        @value = object["mutate"]["literal"]
      end
      def print(output, literal)
        # %0 = integer_literal $Builtin.Int64, 0          // user: %1
        literal.print(output, @value)
      end
    end
  end
end
