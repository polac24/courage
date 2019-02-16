require_relative "courage_sil_function_mutation"

module Courage

  module Mutation

    class SILCallMutation
      def initialize(object)
        @required = SILCallMutationRequired.new(object["required"])
        @actions = SILCallMutationActions.new(object["actions"])
        @name = object["name"]
      end
      def name
        @name
      end
      def count(function)
        @required.calls(function).count
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
            potential_calls = @required.call_blocks(block, 0)
            if potential_calls.count <= left_index
              block.print(output)
              left_index -= potential_calls.count
            else
              call_index = potential_calls[left_index]
              print_block_with_mutation(block, block.calls[call_index], output)
              left_index = nil
            end
          end
        end
        function.print_end(output)
      end
      private def print_block_with_mutation(block, call, output)
          block.print_head(output)
          call_index = call.line_number
          block.body[0...call_index].each{|x| output.puts(x[:value])}
          @actions.print(output, call, @required.call_pattern)
          block.body[(call_index+1)..-1].each{|x| output.puts(x[:value])}
      end
    end

    class SILCallMutationRequired
      def initialize(object)
        @call_pattern = object["call_pattern"]
        @call_pattern_regex = /#{Regexp.quote(object["call_pattern"])}/
      end
      def call_pattern
        @call_pattern
      end
      def call_blocks(building_block, offset)
        indexes = []
        all_calls = building_block.calls
        for i in 0...all_calls.count
          indexes.push(i+offset) if all_calls[i].name =~ @call_pattern_regex
        end
        indexes
      end
      def calls(function)
        building_blocks = function.building_blocks
        indexes = []
        calls_offset = 0
        for i in 0...building_blocks.count
          indexes.concat(call_blocks(building_blocks[i], calls_offset))
          calls_offset += building_blocks[i].calls.count
        end
        indexes
      end
    end
    class SILCallMutationActions
      def initialize(object)
        @replace = object["mutate"]["replace"]
      end
      def print(output, call, what)
        call.print(output, what, @replace)
      end
    end
  end
end