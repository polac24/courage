require 'yaml'

module Fastlane

  module Helper
    class SILMutations
      def initialize(blocks)
        @blocks = blocks
        @all_functions = blocks.select{|x| x.type == "function"}.map{|function|
          function.definition.function_name
        }
        thing = YAML::load_file(File.join(__dir__, 'reversedArray.yml'))
        mutation_defs = thing.map{ |mutation_representation| 
          SILGenericMutation.new(mutation_representation["mutation"])
        }
        all_mutations = []
        blocks.each { |block|
          mutation_defs.each{|mutation|
            if mutation.isSupported(block)
              all_mutations.append({block: block, mutation: mutation})
            end
          }
        }
        @all_mutations = all_mutations
      end
      def print_mutation(i, output)
        mutation = @all_mutations[i]
        block = mutation[:block]
        mutation_representation = mutation[:mutation]

        @blocks.each do  |parse|
          if parse.type == "function" && parse.definition == block.definition
            # mutate
            mutation_representation.print_mutation(block, @all_functions, output)
          else
            parse.print(output)
          end
        end

        "#{mutation_representation.name} for #{block.human_name}"
      end
      def print_mutation_to_file(index, fileName)
        output = File.open(fileName,"w" )
        mutation_summary = print_mutation(index, output)
        output.close
        mutation_summary
      end
      def mutationsCount
        @all_mutations.count
      end
    end

    class SILGenericMutation
      def initialize(object)
        @required = SILGenericMutationRequired.new(object["required"])
        @actions = SILGenericMutationActions.new(object["actions"])
        @name = object["name"]
      end
      def name
        @name
      end
      def isSupported(function)
        return false unless function.type == "function"
        return false unless FunctionMutation.isSupported(function) 
        return false unless @required.isSupported(function)
        return true
      end
      def print_mutation(function, all_functions, output)
        function.human_name.print(output)
        function.definition.print(output)
        function.building_blocks[0..-2].each {|x| x.print(output)}
        # last withtout return line
        function.building_blocks[-1].print_head(output)
        function.building_blocks[-1].body[0..-2].each {|x| output.puts x[:value]}
        return_index, available = function.building_blocks[-1].body[-1][:value].match(/return %(\d+).*\/\/.*id:.*%(\d+)/).captures

        @actions.before_return.print(output, available.to_i, return_index.to_i)

        output.puts (function.end[:value])
        output.puts ""

        @actions.after_return.print_after_function(output, all_functions)
      end
    end

    class SILGenericMutationRequired
      def initialize(object)
        @expected_return = object["return"]
      end
      def isSupported(function)
        function.definition.return_type.to_s == @expected_return
      end
    end
    class SILGenericMutationActions
      def initialize(object)
        @before_return = SILGenericMutationAction.new(object["before_function_return"])
        @after_return = SILAfterFunctions.new(object["after_function"])
      end
      def before_return
        @before_return
      end
      def after_return
        @after_return
      end
    end

    class SILGenericMutationAction
      def initialize(object)
        if object.is_a? String
          @string = object
        elsif object["file"]
          @fileName = object["file"]
        end
      end
      def print(output, available_index, return_index)
        unless @string.nil?
          output.puts(@string.gsub(/%(\d+)/) {|num| "%#{num[1..-1].to_i+available_index}"}.gsub(/#0/, "%#{return_index}"))
          return 
        end
        unless @fileName.nil?
          File.open(File.join(__dir__, @fileName), 'r') do |f1|  
            while line = f1.gets  
              output.puts line
            end  
          end 
        end
      end
    end

    class SILAfterFunctions
      def initialize(object)
        @functions = object.map{|x|
          SILAfterFunctionMutationAction.new(x)
        }
      end
      def print_after_function(output, already_defined_functions)
        @functions.each {|x|
          x.print_after_function(output, already_defined_functions)
        }
      end
    end
    class SILAfterFunctionMutationAction < SILGenericMutationAction
      def initialize(object)
        super(object)
        @external_symbol_name = object["external_symbol_name"]
      end
      def print_after_function(output, already_defined_functions)
        unless already_defined_functions.include? @external_symbol_name
          print(output, 0, 0)
        end
      end
    end

    class SILMutations2
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
