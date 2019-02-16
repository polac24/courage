require_relative "courage_sil_dependency"
require_relative "courage_sil_function_mutation"

module Courage

  module Mutation
    class SILGenericMutation
      def initialize(object)
        @required = SILGenericMutationRequired.new(object["required"])
        @actions = SILGenericMutationActions.new(object["actions"])
        @replaces = SILGenericMutationVariables.new(object)
        @name = object["name"]
      end
      def name
        @name
      end
      def count(function)
        1
      end
      def isSupported(function, allowed_symbols)
        return false unless FunctionMutation.isSupported(function, allowed_symbols) 
        return false unless @required.isSupported(function)
        return true
      end
      def print_mutation(function, index, all_symbols, output)
        if @actions.replace_all.nil?
          print_mutation_append(function, index, all_symbols, output)
        else
          print_mutation_replace(function, index, all_symbols, output)
        end 
      end
      private def print_mutation_append(function, index, all_symbols, output)
        variables = @replaces.replaces(function)
        function.human_name.print(output)
        function.definition.print(output)
        # until return bb
        return_bb_index = function.building_blocks.index {|x| x.has_return}
        function.building_blocks[0...return_bb_index].each {|x| x.print(output)}
        # until return line
        return_bb = function.building_blocks[return_bb_index]
        return_position_index = return_bb.return_position_index
        return_bb.print_head(output)
        return_bb.body[0...return_position_index].each {|x| output.puts x[:value]}
        return_index, available = return_bb.body[return_position_index][:value].match(/return %(\d+).*\/\/.*id:.*%(\d+)/).captures

        @actions.before_return.print(output, available.to_i, return_index.to_i, variables)
        return_bb.body[return_position_index+1..-1].each {|x| output.puts x[:value]}

        #other bb 
        function.building_blocks[(return_bb_index+1)..-1].each {|x| x.print_with_offset(output, @actions.before_return.offset, return_index.to_i)}
        output.puts (function.end[:value])
        output.puts ""

        @actions.dependencies.print_after_function(output, all_symbols)
      end

      private def print_mutation_replace(function, index, all_symbols, output)
        function.human_name.print(output)
        function.definition.print(output)

        function.building_blocks[0].print_head(output)
        @actions.replace_all.print(output, (function.building_blocks[0].arguments_count - 1), 0, [])
        output.puts (function.end[:value])
        output.puts ""
      end
    end

    class SILGenericMutationRequired
      def initialize(object)
        @expected_return = object["return"]
      end
      def isSupported(function)
        case @expected_return
        when String
          return function.definition.return_type.to_s == @expected_return
        when Hash
          return false unless function.definition.return_type.type.to_s == @expected_return["type"]
          return false unless function.definition.return_type.isGeneric == !@expected_return["generic"].nil?
          return true
        end
        return false
      end
    end

    class SILGenericMutationVariables
      def initialize(object)
        @expected_return = object["required"]["return"]
      end
      def replaces(function)
        replaces_for_type(@expected_return, function.definition.return_type)
      end
      def replaces_for_type(object, type)
        return [] unless !object.nil?
        replaces = []
        if !object["variable"].nil?
          replaces.push({key:"@#{object["variable"]}", value: type.to_s})
        end
        replaces.concat(replaces_for_type(object["generic"], type.generics.join(","))) unless !type.is_a?(Parser::Type) || !type.isGeneric || object["generic"].nil?
        replaces
      end
    end
    
    class SILGenericMutationActions
      def initialize(object)
        @before_return = nil
        @replace_all = nil
        @before_return = SILGenericMutationAction.new(object["before_function_return"]) if !object["before_function_return"].nil?
        @replace_all = SILGenericMutationAction.new(object["replace"]) if !object["replace"].nil?
        @dependencies = SILDependencies.new(object["dependencies"])
      end
      def before_return
        @before_return
      end
      def dependencies
        @dependencies
      end
      def replace_all
        @replace_all
      end
    end

    class SILGenericMutationAction
      def initialize(object)
        return nil if object.nil?
        @string = object["return"]
        @offset = 0
        @offset = object["offset"] if !object["offset"].nil?
      end
      def print(output, offset_index, return_index, variables)
        unless @string.nil?
          line = SILGenericMutationAction.modifyLine(@string, offset_index, 0, return_index, variables)
          output.puts(line)
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
      def self.modifyLine(line_input, offset_index, rewrite_index_start, return_index, variables)
        line = line_input.gsub(/%(\d+)/) {|num| 
          matched_var_index = num[1..-1].to_i
          matched_var_index += offset_index if matched_var_index > rewrite_index_start
          "%#{matched_var_index}"
        }
        line = line.gsub(/#0/, "%#{return_index}")
        line = variables.reduce(line){|prev_line, replace|
          prev_line.gsub(/#{replace[:key]}/, replace[:value])
        }
        line
      end
      def offset
        @offset
      end
    end
  end
end