require 'fastlane_core/ui/ui'

module Fastlane
  UI = FastlaneCore::UI unless Fastlane.const_defined?("UI")

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
        line = line_obj[:value]
        @type = "function_comment"
        @name = line[/\/\/\s(.*)/, 1]
      end
    end

    class SILFunctionDefinition < SILBlock
      def initialize(line_obj)
        super([line_obj])
        @type = "function_definition"
        line = line_obj[:value]
        parsed_tokens = []
        function = {}
        @isExternal = false

        return_string_index_start = 0
        convention_index = line.index(": $@convention(")

        tokens_definition = line[0..(convention_index-1)].split(' ')
        tokens_definition.each_with_index do |token, index| 
          if token == "sil"
            parsed_tokens.append({type:"sil", value:token})
          elsif token.start_with?("[")
            parsed_tokens.append({type:"attribute", value:token[/[(.*)]]/, 1]})
          elsif token.start_with?("@$")
            parsed_tokens.append({type:"name", value:token})
          elsif token.end_with?("_external")
            @isExternal = true
            parsed_tokens.append({type:"external", value:token})
          else
            parsed_tokens.append({type:"other", value:token})
          end
        end
        second_part = line[convention_index + 2...line.length]
        return_string=second_part[(second_part.index(")")+1)..second_part.index("{")]

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
      private def parse_return_type(return_type)
        return return_type.gsub(/@\S*\s/,'')
      end
    end

    class Type
      def self.build(type)
        type = type.strip
        if match = type.match(/^(.*).Type$/)
          type = match.captures
          return TypeType.new(type)
        end
        if match = type.match(/^([^<]*)<(.*)>$/)
          type, generic = match.captures
          return Generic.new(type,generic)
        end
        if match = self.read_function_type(type)
          argument, return_type = match
          return Closure.new(argument,return_type)
        end
        return Type.new(type)
      end
      def self.read_function_type(return_definition)
        brackets_level = 0
        chars = return_definition.split("")
        function_separator_index = chars.zip(chars.drop(1)).index{ |c,n|
          if c == "("
            brackets_level += 1
          elsif c == ")"
            brackets_level -= 1
          elsif c == "-" && n == ">" && brackets_level == 0
            next true
          end
          false
        }
        return nil unless function_separator_index
        argument_type = return_definition[0..function_separator_index-1]
        return_type = return_definition[function_separator_index + 3..-1]
        return argument_type, return_type
      end
      def initialize(name)
        @type = name
      end
      def type
        @type
      end
      def isGeneric
        return false
      end
      def isClosure
        return false
      end
      def isType
        return false
      end
      def to_s
        @type
      end
    end

    class Generic < Type
      def initialize(name,genericString)
        @type = Type.build(name)
        @generics = genericString.split(",").map{|x| Type.build(x)}
      end
      def type
        return @type
      end
      def generics
        return @generics
      end
      def isGeneric
        return true
      end
      def hasGenericClosure
        @generics.any? {|x| x.isClosure}
      end
      def to_s
        generics = @generics.join(",")
        "#{@type}<#{generics}>"
      end
    end
    class Closure < Type
      def initialize(arguments,return_type)
        @arguments = Type.build(arguments)
        @return_type = Type.build(return_type)
      end
      def isClosure
        return true
      end
      def to_s
        "#{@arguments}->#{@return_type}"
      end
    end
    class TypeType < Type
      def initialize(name)
        @typeType = name
      end
      def isType
        return true
      end
      def to_s
        "#{@typeType}.Type"
      end
    end

    class SILBuildingBlock < SILBlock
      def initialize(lines)
        super(lines)

        definition_index = self.class.find_index("bb_start", lines, 0)
        @comments = lines.first(definition_index)
        @definition = lines[definition_index]
        @index = parse_block_number(lines[definition_index])
        @arguments_count = parse_block_arguments(lines[definition_index][:value])
        @body = lines.drop(definition_index+1)
      end

      def print(output)
        @comments.each{|x| output.puts x[:value]}
        output.puts(@definition[:value])
        @body.map{|x| output.puts x[:value]}
      end
      private def parse_block_number(line)
        return [/bb(\d*)/, 1]
      end
      private def parse_block_arguments(line)
        return line.scan(/%(\d*)/)
      end
    end

    class SILParser
      # class methods that you define here become available in your action
      # as `Helper::SILParser.your_method`
      def initialize(path)
        @path = path

        tokens = tokenize(@path)
        @parsed = parse(tokens)
      end


      def printToFile(fileName)
        output = File.open( fileName,"w" )
        print(output)
        output.close
      end

      def print(output)

        @parsed.each do  |parse|
          if parse.type == "static"
             parse.print(output)
          elsif parse.type == "function" && !parse.definition.isExternal && parse.definition.return_type.isGeneric && parse.definition.return_type.type.type == "Optional" && !parse.definition.return_type.hasGenericClosure
            parse.print(output)
          else
            parse.print(output)
          end

        end
      end


      def parse(tokens)
        parsed = []
        index = 0
        nextFunction = SILBlock.find_index("function_body_start", tokens, index).to_i - 1
        while nextFunction > 0
          if nextFunction  > (index + 1) 
            # parsed.append({type:"static", lines:tokens[index..(nextFunction-2)]})
            parsed.append(SILBlock.new(tokens[index..(nextFunction-1)]))
          end
          #parsed.append({type:"function", function:parse_next_function(tokens, nextFunction - 1)})
          index = SILBlock.find_index("end", tokens, nextFunction)+1
          parsed.append(SILFunction.new(tokens[nextFunction...(index)]))

          nextFunction = SILBlock.find_index("function_body_start", tokens, index).to_i - 1
        end
        #rest of static
        parsed.append(SILBlock.new(tokens.drop(index)))
      end

      def tokenize(path)
        number = 0
        tokens = []
        File.readlines(path).each do |line|
          line = line.chomp
          new_token = {}
          if line.start_with?("sil ") 
            if line.end_with?("{") 
              new_token[:type]="function_body_start"
            else
              new_token[:type]="function_definition"
            end
          elsif line.start_with?("  ")
           new_token[:type]="nested"
          elsif line.start_with?("//")
            new_token[:type]="comment"
          elsif line.start_with?("bb")
            new_token[:type]="bb_start"
          elsif line.start_with?("}")
            new_token[:type]="end"
          elsif line == ""
            new_token[:type]="empty"
          else 
            new_token[:type]="unknown"
          end

          new_token[:value]=line
          new_token[:number]=number
          tokens.append(new_token)
          number += 1
        end

        return tokens
      end
    end
  end
end
