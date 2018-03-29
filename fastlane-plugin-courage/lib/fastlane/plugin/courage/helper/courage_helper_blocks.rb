
module Fastlane

  module Helper
    class SILBlock
      def self.nextBlock(provider)
        lines = []
        loop do
          line = provider.peek_forward
          break if line.nil?
          case line[:type]
          when "function_body_start"
            return SILBlock.new(lines) if lines.count > 0 
            return SILFunction.build(provider)
          when "function_definition"
            return SILBlock.new(lines) if lines.count > 0 
            return SILFunctionHeader.build(provider)
          when "global_variable"
            return SILBlock.new(lines) if lines.count > 0 
            return SILGlobalVariable.build(provider)
          else
            lines.push(provider.read)
          end
        end
        return SILBlock.new(lines) if lines.count > 0 
        nil
      end
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
    class SILGlobalVariable < SILBlock
      def self.build(provider)
        lines = [provider.read, provider.read]
        SILGlobalVariable.new(lines)
      end
      def initialize(lines)
        super(lines)
        @type = "global_variable"
        @human_name = SILFunctionComment.new(lines[0])
        @definition = SILGlobalDefinition.new(lines[1])
      end
      def definition
        return @definition
      end
      def human_name
        return @human_name
      end
      def print(output)
        @human_name.print(output)
        @definition.print(output)
      end
    end
    class SILFunctionHeader < SILBlock
      def self.build(provider)
        lines = [provider.read, provider.read]
        SILFunctionHeader.new(lines)
      end
      def initialize(lines)
        super(lines)
        @type = "function_definition"
        @human_name = SILFunctionComment.new(lines[0])
        @definition = SILFunctionDefinition.new(lines[1])
      end
      def definition
        return @definition
      end
      def human_name
        return @human_name
      end
      def print(output)
        @human_name.print(output)
        @definition.print(output)
      end
    end
    class SILFunction < SILFunctionHeader
      def self.build(provider)
        lines = []
        loop do
          line = provider.read
          lines.append(line)
          break if line[:type] == "end"
        end
        SILFunction.new(lines)
      end
      def initialize(lines)
        super(lines)
        @type = "function"

        @building_blocks = parse_building_blocks(lines.drop(2)[0...-1])
        @end = lines.last
      end
      def print(output)
        super(output)
        @building_blocks.each {|x| x.print(output)}
        print_end(output)
      end
      def print_header(output)
        SILFunctionHeader.instance_method(:print).bind(self).call(output)
      end
      def print_end(output)
        output.puts (@end[:value])
        output.puts ""
      end
      def building_blocks
        return @building_blocks
      end
      def end
        return @end
      end

      # private def parse_function_name(line)
      #   return {name: line[:value][/\/\/\s(.*)/, 1], value:line[:value]}
      # end
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
        @function_name = ""
        @attributes = []

        return_string_index_start = 0
        convention_index = @line.index(": $@convention(")

        tokens_definition = @line[0..(convention_index-1)].split(' ')
        tokens_definition.each_with_index do |token, index| 
          if token == "sil"
            parsed_tokens.append({type:"sil", value:token})
          elsif token.start_with?("[")
            @attributes.append(token[/\[(.*)\]/, 1])
          elsif token.start_with?("@")
            parsed_tokens.append({type:"name", value:token})
            @function_name = token
          elsif token.end_with?("_external")
            @isExternal = true
            parsed_tokens.append({type:"external", value:token})
          else
            parsed_tokens.append({type:"other", value:token})
          end
        end
        second_part = @line[convention_index + 2...@line.length]
        end_index = second_part.size
        end_index = second_part.index("{") unless second_part.index("{").nil?
        return_string=second_part[(second_part.index(")")+1)..(end_index-1)]

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
      def name
        @function_name
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
        return "#{@function_name} : #{@argument_type}->#{@return_type}"
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
        @accesses = SILAccess.readAll(ContentProvider.new(@body))
      end
      def arguments_count
        @arguments_count
      end
      def body
        @body
      end
      def accesses
        @accesses
      end
      def print(output)
        print_head(output)
        @body.map{|x| output.puts x[:value]}
      end
      def print_with_offset(output, offset)
        print_head(output)
        @body.map{|x|
          SILGenericMutationAction.modifyLine(x, offset, "", [])
        }.each{|x| output.puts x[:value]}
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
    class SILGlobalDefinition < SILBlock
      def initialize(line)
        super ([line])
        tokens = line[:value].split(' ')
        tokens.each{|x|
          if x.start_with?("@_")
            @name = x
          end
        }
      end
      def name
        @name
      end
    end
    class SILAccess
      def self.readAll(lines_provider)
        accesses = []
        loop do
          line = lines_provider.peek
          break if line.nil?
          if line[:type] == "begin_access"
              accesses.push(SILAccess.new(lines_provider))
          end
          lines_provider.read
        end
        accesses
      end
      def initialize(lines_provider)
        @line_number = lines_provider.index
        line = lines_provider.read
        @id, modifiers, @access_id, @type = line[:value].match(/%(\d+) = begin_access([\s\S\[\]]*) %(\d+) : \$\*(\S*) /).captures
        @modifiers = modifiers.match(/\[(\S+)\]/).captures
        @offset_end = find_end_access(lines_provider, @id, @type)
        @last_used_ids = find_end_ids(lines_provider, @offset_end)
      end
      def access_type
        @type
      end
      def line_number
        @line_number
      end
      def is_writeable
        @modifiers.include?("modify")
      end
      def id
        @id
      end
      def offset_end
        @offset_end
      end
      def last_used_ids
        @last_used_ids
      end
      def to_s
        "id: #{@id}, end_offset: #{@offset_end}, type: #{@type}, on: #{@access_id}, last_id: #{@last_used_ids}"
      end
      private def find_end_access(lines_provider, id, type)
        i = 1
        loop do
          line = lines_provider.peek_custom(i)
          return nil if line.nil?
          return i if / end_access %#{id} : \$\*#{type} /.match? (line[:value])
          i += 1
        end
      end
      private def find_end_ids(lines_provider, i)
        line = lines_provider.peek_custom(i)
        return line[:value].match(/\/\/\sid:\s%(\d+)/ ).captures[0].to_i
     end
    end
  end
end
