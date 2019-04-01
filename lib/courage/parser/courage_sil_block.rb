
module Courage

  module Parser
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
          when "coverage_map"
            return SILBlock.new(lines) if lines.count > 0 
            return SILCoverageMap.build(provider)
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
      def name
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

    class SILCoverageMap < SILBlock
      def self.build(provider)
        lines = []
        loop do
          line = provider.read
          lines.append(line)
          break if line[:type] == "end"
        end
        SILCoverageMap.new(lines)
      end
      def initialize(lines)
        super(lines)
        @file_name, @name, @human_name= lines[1][:value].match(/sil_coverage_map\s*"([^"]+)"\s"?([^\s"]*)"?.*{\s*\/\/\s*(.*)/).captures
        # append @ at the front to match sil definition
        @name = "@#{@name}"
      end
      def file_name
        @file_name
      end
      def name
        @name
      end
      def human_name
        @human_name
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
        @literals = SILLiteral.readAll(ContentProvider.new(@body))
        @structs = SILStruct.mapAll(ContentProvider.new(@body))
        @calls = SILCall.mapAll(ContentProvider.new(@body))
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
      def literals
        @literals
      end
      def structs
        @structs
      end
      def calls
        @calls
      end
      def print(output)
        print_head(output)
        @body.map{|x| output.puts x[:value]}
      end
      def print_with_offset(output, offset, offset_start)
        print_head(output)
        @body.map{|x|
          SILGenericMutationAction.modifyLine(x[:value], offset, offset_start, "", [])
        }.each{|x| output.puts x}
      end
      def print_head(output)
        @comments.each{|x| output.puts x[:value]}
        output.puts(@definition[:value])
      end
      def has_return
        !return_position_index.nil?
      end
      def return_position_index
        # return could be in a last bb (-1) or followed by empty line (other bb)
        potential_return_indexes = [@body.length-1,@body.length-2]
        potential_return_indexes.find {|i|
          i if @body[i][:type] == "return"
        }
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
          line = lines_provider.peek()
          break if line.nil?
          if line[:type] == "begin_access"
              accesses.push(SILAccess.new(lines_provider))
          elsif line[:type] == "store"
              accesses.push(SILFreeFallAccess.new(lines_provider))
          else
              lines_provider.read()
          end
        end
        accesses
      end
      def initialize(lines_provider)
        @line_number = lines_provider.index
        line = lines_provider.read()
        @id, modifiers, @access_id, @type = line[:value].match(/%(\d+) = begin_access([\s\S\[\]]*) %(\d+) : \$\*(\S*) /).captures
        @modifiers = modifiers.match(/\[(\S+)\]/).captures
        @offset_end, @last_stored_id , @last_used_ids = read_to_end_access(lines_provider, @id, @type)
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
        @id.to_i
      end
      def offset_end
        @offset_end
      end
      def access_id
        @access_id
      end
      def last_used_ids
        @last_used_ids
      end
      def last_stored_id
        @last_stored_id
      end
      def to_s
        "id: #{@id}, end_offset: #{@offset_end}, type: #{@type}, on: #{@access_id}, last_id: #{@last_used_ids}, last_stored_id: #{@last_stored_id}"
      end
      private def read_to_end_access(lines_provider, id, type)
        i = 0
        last_store_id = nil
        end_id = nil

        loop do
          line = lines_provider.read()
          return [nil, nil, nil] if line.nil?

          if match = line[:value].match(/\/\/\sid:\s%(\d+)/ )
            end_id = match.captures[0].to_i
          end
          if match = line[:value].match(/store %(\d+) to %#{id} : \$\*#{type}/ )
            last_store_id = match.captures[0].to_i
          end
          break if / end_access %#{id} : \$\*#{type} /.match? (line[:value])
          i += 1
        end
        return [i, last_store_id, end_id]
      end
    end

    class SILFreeFallAccess < SILAccess
      def initialize(lines_provider)
        @line_number = lines_provider.index
        line = lines_provider.read()
        last_stored_id, @access_id, @type, @id = line[:value].match(/ store %(\d+) to %(\d+) : \$\*(\S*)\s* \/\/ id: %(\d+)/).captures
        @last_used_ids = @id.to_i
        @last_stored_id = last_stored_id.to_i
        @modifiers = []
        @offset_end = 1
      end
      def is_writeable
        true
      end
    end

    class SILLiteral
      def self.readAll(lines_provider)
        literals = []
        loop do
          line = lines_provider.peek()
          break if line.nil?
          if line[:type] == "literal"
              literals.push(SILLiteral.new(lines_provider))
          else
              lines_provider.read()
          end
        end
        literals
      end
      def initialize(lines_provider)
        @line_number = lines_provider.index
        line = lines_provider.read()
        ##   %0 = integer_literal $Builtin.Int64, 0          // user: %1
        id, @literal_name, @type, @value, @user_section = line[:value].match(/%(\d+) = (\S*_literal) (\S*) (.*)\s*\/\/ user(.*)/).captures
        @id = id.to_i
      end
      def id
        @id
      end
      def line_number
        @line_number
      end
      def literal_name
        @literal_name
      end
      def type
        @type
      end
      def value
        @value
      end
      def print(output, value)
        output.puts(" %#{@id} = #{@literal_name} #{type} #{value}          // user#{@user_section}\n")
      end
    end

    class SILStruct
      def self.mapAll(lines_provider)
        structs = []
        loop do
          line = lines_provider.peek()
          break if line.nil?
          if line[:type] == "struct"
              structs.push(SILStruct.new(lines_provider))
          else
              lines_provider.read()
          end
        end
        structs.map{ |x| [x.id, x] }.to_h
      end
      def initialize(lines_provider)
        @line_number = lines_provider.index
        line = lines_provider.read()
        ##   %6 = struct $Double (%5 : $Builtin.FPIEEE64)    // user: %7
        id, @type, source_id, @source_type, @user_section = line[:value].match(/%(\d+) = struct (\S*) \(%(\d+) \: (.*)\)\s*(\/\/ user(.*))?/).captures
        @id = id.to_i
        @source_id = source_id.to_i
      end
      def id
        @id
      end
      def line_number
        @line_number
      end
      def source_id
        @source_id
      end
      def type
        @type
      end
      def value
        @value
      end
      def print(output)
        output.puts(" %#{@id} = struct #{@source_type} (%#{source_id} : #{source_type})          // user#{@user_section}\n")
      end
    end

    class SILCall
      def self.mapAll(lines_provider)
        calls = []
        loop do
          line = lines_provider.peek()
          break if line.nil?
          if line[:type] == "builtin_call"
              calls.push(SILCall.new(lines_provider))
          else
              lines_provider.read()
          end
        end
        calls
      end
      def initialize(lines_provider)
        @line_number = lines_provider.index
        line = lines_provider.read()
        ##    %15 = builtin "sadd_with_overflow_Int64"(%12 : $Builtin.Int64, %13 : $Builtin.Int64, %14 : $Builtin.Int1) : $(Builtin.Int64, Builtin.Int1) // users: %17, %16
        ##  %51 = builtin "ptrtoint_Word"(%49 : $Builtin.RawPointer) : $Builtin.Word // user: %55
        id, @name, @input, @output = line[:value].match(/%(\d+) = builtin "(\S+)"\((.*)\) : \$(.*?)(\/\/|$)/).captures
        @id = id.to_i
      end
      def id
        @id
      end
      def line_number
        @line_number
      end
      def name
        @name
      end
      def print(output, old_pattern, new_pattern)
        new_name = @name.gsub(old_pattern, new_pattern)
        output.puts("  %#{@id} = builtin \"#{new_name}\"(#{@input}) : $(#{@output})         //\n")
      end
    end
  end
end
