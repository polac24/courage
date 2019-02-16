require_relative "courage_sil_function_mutation"
require_relative "courage_sil_generic_mutation"

module Courage

  module Mutation

    class SILAccessMutation
      def initialize(object)
        @required = SILAccessMutationRequired.new(object["required"])
        @actions = SILAccessMutationActions.new(object["actions"])
        @name = object["name"]
      end
      def name
        @name
      end
      def count(function)
        @required.accesses(function).count
      end
      def to_s
        @name
      end
      def isSupported(function, allowed_symbols)
        return false unless FunctionMutation.isSupported(function, allowed_symbols) 
        return false unless @required.isSupported(function)
        return true
      end
      def print_mutation(function, i, all_symbols, output)
        function.print_header(output)
        left_index = i
        offset = 0
        offset_start = 0
        building_blocks = function.building_blocks
        for block in building_blocks
          if left_index.nil?
            block.print_with_offset(output, offset, offset_start)
          else
            potential_mutations = @required.accesses_block(block, 0)
            if potential_mutations.count <= left_index
              block.print(output)
              left_index -= potential_mutations.count
            else
              access_index = potential_mutations[left_index]
              offset, offset_start = print_block_with_mutation(block, block.accesses[access_index], output)
              left_index = nil
            end
          end
        end
        function.print_end(output)

        @actions.dependencies.print_after_function(output, all_symbols)
      end
      private def print_block_with_mutation(block, access, output)
          block.print_head(output)
          access_ending_index = access.line_number + access.offset_end
          block.body[0...access_ending_index].each{|x| output.puts(x[:value])}
          available_id = access.last_used_ids
          @actions.print(output, available_id, access.access_id)
          new_value_id = available_id+@actions.stored_value
          new_builtin_value_id = available_id+@actions.builtin_value
          block.body[(access_ending_index)..-1].map{|x| 
            replace_lookup = [{key:"%#{access.last_stored_id}\\s", value:"%#{new_value_id} "}]
            # builtin literal id to also replace
            replace_lookup.push({key:"%#{block.structs[access.last_stored_id].source_id}\\s", value:"%#{new_builtin_value_id} "}) if block.structs.key?(access.last_stored_id)
            SILGenericMutationAction.modifyLine(x[:value], @actions.offset, access.id, "", replace_lookup)
          }.each{|x| output.puts(x)}

          [@actions.offset, access.id]
      end
    end
    class SILAccessMutationRequired
      def initialize(object)
        @type = object["type"]
      end
      def accesses(function)
        building_blocks = function.building_blocks
        indexes = []
        access_offset = 0
        for i in 0...building_blocks.count
          indexes.concat(accesses_block(building_blocks[i], access_offset))
          access_offset += building_blocks[i].accesses.count
        end
        indexes
      end
      def accesses_block(building_block, offset)
        indexes = []
        all_accesses = building_block.accesses
        for i in 0...all_accesses.count
          indexes.push(i+offset) if all_accesses[i].access_type == @type && all_accesses[i].is_writeable
        end
        indexes
      end
      def isSupported(function)
        accesses(function).count > 0
      end
    end
    class SILAccessMutationActions
      def initialize(object)
        @action = SILGenericMutationAction.new(object["mutate"])
        @offset = 0
        @offset = object["offset"] if !object["offset"].nil?
        @stored_value = object["stored_value"]
        @builtin_value = object["builtin_value"]
        @dependencies = SILDependencies.new(object["dependencies"])
      end
      def offset
        @offset
      end
      def stored_value
        @stored_value
      end
      def builtin_value
        @builtin_value
      end
      def action
        @action
      end
      def dependencies
        @dependencies
      end
      def print(output, available_index, return_index)
        @action.print(output, available_index, return_index, [])
      end
    end
  end
end