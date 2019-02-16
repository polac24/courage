require 'yaml'
require_relative "courage_sil_generic_mutation"
require_relative "courage_sil_access_mutation"
require_relative "courage_sil_literal_mutation"
require_relative "courage_sil_call_mutation"

module Courage

  module Mutation
    class SILMutations
      def initialize(blocks, allowed_symbols)
        @blocks = blocks
        @all_symbols = blocks.select{|x| supported_block_types.include?(x.type)}.map{|function|
          function.definition.name
        }

        thing = YAML::load_file(File.join(__dir__, 'all.yml'))
        mutation_defs = thing.map{ |mutation_representation| 
          if !mutation_representation["mutation"].nil?
            SILGenericMutation.new(mutation_representation["mutation"])
          elsif !mutation_representation["access_mutation"].nil?
            SILAccessMutation.new(mutation_representation["access_mutation"])
          elsif !mutation_representation["literal_mutation"].nil?
            SILLiteralMutation.new(mutation_representation["literal_mutation"])
          elsif !mutation_representation["call_mutation"].nil?
            SILCallMutation.new(mutation_representation["call_mutation"])
          end
        }
        all_mutations = []
        blocks.each { |block|
          mutation_defs.each{|mutation|
            if mutation.isSupported(block, allowed_symbols)
              new_mutations = (0...mutation.count(block)).map{|x|
                {block: block, mutation: mutation, index:x}
              }
              all_mutations.concat(new_mutations)
            end
          }
        }
        @all_mutations = all_mutations
      end

      def supported_block_types() 
        ["function", "function_definition", "global_variable"]
      end

      def print_mutation(i, output)
        mutation = @all_mutations[i]
        block = mutation[:block]
        mutation_representation = mutation[:mutation]
        mutation_index = mutation[:index]

        @blocks.each do  |parse|
          if parse.type == "function" && parse.definition == block.definition
            # mutate
            mutation_representation.print_mutation(block, mutation_index, @all_symbols, output)
          else
            parse.print(output)
          end
        end

        mutation_name(i)
      end
      def print_mutation_to_file(index, fileName)
        output = File.open(fileName,"w" )
        mutation_summary = print_mutation(index, output)
        output.close
        mutation_summary
      end
      def mutation_name(i)
        "#{@all_mutations[i][:mutation].name} for #{@all_mutations[i][:block].human_name}"
      end
      def mutationsCount
        @all_mutations.count
      end
    end
  end
end
