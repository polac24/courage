
module Fastlane

  module Helper
    class SILBlock
      def initialize(lines)
        @lines = lines
        @type = "static"
      end
      def print(output)
        @lines.each{|x| output.puts x[:value]}
      end
      def type
        @type
      end
      def lines
        @lines
      end
      def self.find_index(type, tokens, fromIndex)
        i = tokens.drop(fromIndex).index { |token| token[:type] == type} 
        if i.nil?
          return nil
        end
        return i + fromIndex
      end
      def to_s
        @lines.join("\n")
      end
    end

    class SILFunction < SILBlock
      def initialize(lines)
        super(lines)
        @type = "function"

        @human_name = SILFunctionComment.new(lines[0])
        @definition = SILFunctionDefinition.new(lines[1])
        @building_blocks = parse_building_blocks(lines.drop(2)[0...-1])
        @end = lines.last
      end
      def print(output)
        @human_name.print(output)
        @definition.print(output)
        @building_blocks.each {|x| x.print(output)}
        output.puts (@end[:value])
        output.puts ""
      end
      def definition
        return @definition
      end

      private def parse_function_name(line)
        return {name: line[:value][/\/\/\s(.*)/, 1], value:line[:value]}
      end
      private def parse_building_blocks(lines)
        parsed_blocks = []
        index = 0
        while index < (lines.count-1) do
          end_bb = self.class.find_index("empty",lines, index) || (lines.count-1)
          parsed_blocks.append(SILBuildingBlock.new(lines[index..end_bb]))
          index = end_bb + 1
        end
        parsed_blocks
      end
    end

    class SILFunctionComment < SILBlock
      def initialize(line_obj)
        super([line_obj])
        @line = line_obj[:value]
        @type = "function_comment"
        @name = @line[/\/\/\s(.*)/, 1]
      end
      def to_s
        @name
      end
    end

    class SILFunctionDefinition < SILBlock
      def initialize(line_obj)
        super([line_obj])
        @type = "function_definition"
        @line = line_obj[:value]
        parsed_tokens = []
        function = {}
        @isExternal = false
        @functionName = ""
        @attributes = []

        return_string_index_start = 0
        convention_index = @line.index(": $@convention(")

        tokens_definition = @line[0..(convention_index-1)].split(' ')
        tokens_definition.each_with_index do |token, index| 
          if token == "sil"
            parsed_tokens.append({type:"sil", value:token})
          elsif token.start_with?("[")
            @attributes.append(token[/\[(.*)\]/, 1])
          elsif token.start_with?("@$")
            parsed_tokens.append({type:"name", value:token})
            @functionName = token
          elsif token.end_with?("_external")
            @isExternal = true
            parsed_tokens.append({type:"external", value:token})
          else
            parsed_tokens.append({type:"other", value:token})
          end
        end
        second_part = @line[convention_index + 2...@line.length]
        return_string=second_part[(second_part.index(")")+1)..(second_part.index("{")-1)]

        argument_type, return_type = Type.read_function_type(parse_return_type(return_string))
        @argument_type = Type.build(argument_type)
        @return_type = Type.build(return_type)
        return function
      end
      def isExternal
        return @isExternal
      end
      def argument_type
        return @argument_type
      end
      def return_type
        return @return_type
      end
      def attributes
        @attributes
      end
      def line
        @line
      end
      def ==(o)
        o.class == self.class && o.line == line
      end
      private def parse_return_type(return_type)
        return return_type.gsub(/@\S*\s/,'')
      end
      def to_s
        return "#{@functionName} : #{@argument_type}->#{@return_type}"
      end
    end

    class SILBuildingBlock < SILBlock
      def initialize(lines)
        super(lines)

        definition_index = self.class.find_index("bb_start", lines, 0)
        @comments = lines.first(definition_index)
        @definition = lines[definition_index]
        @index = parse_block_number(lines[definition_index])
        @arguments_count = parse_block_arguments(lines[definition_index][:value]).count
        @body = lines.drop(definition_index+1)
      end
      def arguments_count
        @arguments_count
      end
      def print(output)
        print_head(output)
        @body.map{|x| output.puts x[:value]}
      end
      def print_head(output)
        @comments.each{|x| output.puts x[:value]}
        output.puts(@definition[:value])
      end
      private def parse_block_number(line)
        return [/bb(\d*)/, 1]
      end
      private def parse_block_arguments(line)
        return line.scan(/%(\d*)/)
      end
    end
  end
end
