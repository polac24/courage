require 'yaml'

module Fastlane

  module Helper
    class SILMutations
      def initialize(blocks)
        @blocks = blocks
        @all_symbols = blocks.select{|x| ["function", "function_definition", "global_variable"].include?(x.type)}.map{|function|
          function.definition.name
        }


        thing = YAML::load_file(File.join(__dir__, 'all.yml'))
        mutation_defs = thing.map{ |mutation_representation| 
          if !mutation_representation["mutation"].nil?
            SILGenericMutation.new(mutation_representation["mutation"])
          elsif !mutation_representation["access_mutation"].nil?
            SILAccessMutation.new(mutation_representation["access_mutation"])
          end
        }
        all_mutations = []
        blocks.each { |block|
          mutation_defs.each{|mutation|
            if mutation.isSupported(block)
              new_mutations = (0...mutation.count(block)).map{|x|
                {block: block, mutation: mutation, index:x}
              }
              all_mutations.concat(new_mutations)
            end
          }
        }
        @all_mutations = all_mutations
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
        @replaces = SILGenericMutationVariables.new(object)
        @name = object["name"]
      end
      def name
        @name
      end
      def count(function)
        1
      end
      def isSupported(function)
        return false unless FunctionMutation.isSupported(function) 
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
          replaces.push({key:object["variable"], value: type.to_s})
        end
        replaces.concat(replaces_for_type(object["generic"], type.generics.join(","))) unless !type.is_a?(Helper::Type) || !type.isGeneric || object["generic"].nil?
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
          prev_line.gsub(/@#{replace[:key]}/, "#{replace[:value]}")
        }
        line
      end
      def offset
        @offset
      end
    end

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
        @symbols = Helper::SILParser.new(File.join(__dir__, file)).symbols
      end
      def print_after_function(output, already_defined_symbols)
        @symbols.each{|symbol|
          symbol.print(output) unless already_defined_symbols.include? symbol.definition.name
        }
      end
    end

    class FunctionMutation
      def self.isSupported(function)
        return false unless function.type == "function"
        return false unless !function.definition.isExternal
        return false unless !function.definition.attributes.include?("transparent")
        return true
      end
    end

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
      def isSupported(function)
        return false unless FunctionMutation.isSupported(function) 
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
          # +2 means that we should include "dealloc_stack"
          access_ending_index = access.line_number + access.offset_end + 2
          block.body[0...access_ending_index].each{|x| output.puts(x[:value])}
          @actions.print(output, access.last_used_ids+1, access.access_id)
          block.body[(access_ending_index)..-1].map{|x| 
            SILGenericMutationAction.modifyLine(x[:value], @actions.offset, access.id, "", [])
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
        @dependencies = SILDependencies.new(object["dependencies"])
      end
      def offset
        @offset
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
