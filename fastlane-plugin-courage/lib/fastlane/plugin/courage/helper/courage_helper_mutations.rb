
module Fastlane

  module Helper
    class SILMutations
      def initialize(blocks)
        @blocks = blocks
        mutation_types = [NopFunction, NilReturnFunction]

        mutations = blocks.select{|x| x.type == "function"}.map {|block|
          blockMutations = []
          mutation_types.each {|mutation|
            blockMutations.append(mutation.new(block)) if mutation.isSupported(block)
          }
          blockMutations 
        }
        @mutations = mutations.reduce([]){|p,n| p.concat(n)}
      end
      def mutationsCount
        @mutations.size
      end
      def print_mutation_to_file(index, fileName)
        output = File.open(fileName,"w" )
        mutation_summary = print_mutation(index, output)
        output.close
        mutation_summary
      end
      def print_mutation(index, output)
        mutation = @mutations[index]
        @blocks.each do  |parse|
          if parse.type == "function" && parse.definition == mutation.definition
            # mutate
            mutation.print(output)
          else
            parse.print(output)
          end
        end
        mutation.to_s
      end
    end

    class FunctionMutation < SILFunction
      def self.isSupported(function)
        return false unless !function.definition.isExternal
        return false unless !function.definition.attributes.include?("transparent")
        return true
      end
    end

    class NopFunction < FunctionMutation
      def initialize(block)
        super(block.lines)
        @argumentsCount = @building_blocks[0].arguments_count
      end
      def self.isSupported(function)
        return false unless super(function)
        return false unless function.definition.return_type.type == "()"
        return true
      end
      def print(output)
        @human_name.print(output)
        @definition.print(output)
        @building_blocks[0].print_head(output)
        print_empty_bb(@argumentsCount, output)
        output.puts (@end[:value])
        output.puts ""
      end
      private def print_empty_bb(startin_index, output)
         output.puts ("  %#{startin_index} = tuple ()                                   // user: %#{startin_index+1}")
         output.puts ("  return %#{startin_index} : $()                                 // id: %#{startin_index+1}")
      end
      def to_s
        return "No operation of #{@human_name}"
      end
    end
    class NilReturnFunction < FunctionMutation
      def initialize(block)
        super(block.lines)
        @argumentsCount = @building_blocks[0].arguments_count
        @generic_optional_type = @definition.return_type.generics[0].type
      end
      def self.isSupported(function)
        return false unless super(function)
        return false unless function.definition.return_type.isGeneric 
        return false unless function.definition.return_type.type.type == "Optional"
        return false unless function.definition.return_type.generics.count == 1
        return false unless function.definition.return_type.generics[0].isSimpleType
        return true
      end
      def print(output)
        @human_name.print(output)
        @definition.print(output)
        @building_blocks[0].print_head(output)
        print_empty_bb(@argumentsCount, @generic_optional_type, output)
        output.puts (@end[:value])
        output.puts ""
      end
      private def print_empty_bb(startin_index, type, output)
         output.puts ("  %#{startin_index} = alloc_stack $Optional<#{type}>              // users: %#{startin_index+1}, %#{startin_index+2}, %#{startin_index+3}")
         output.puts ("  inject_enum_addr %#{startin_index} : $*Optional<#{type}>, #Optional.none!enumelt // id: %#{startin_index+1}")
         output.puts ("  %#{startin_index+2} = tuple ()")
         output.puts ("  %#{startin_index+3} = load %#{startin_index} : $*Optional<#{type}>               // user: %#{startin_index+5}")
         output.puts ("  dealloc_stack %#{startin_index} : $*Optional<#{type}>           // id: %#{startin_index+4}")
         output.puts ("  return %#{startin_index+3} : $Optional<#{type}>                   // id: %#{startin_index+5}")
      end
      def to_s
        return "Return nil of #{@human_name}"
      end
    end
  end
end
