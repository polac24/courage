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
    end

    class SILFunction < SILBlock
      def initialize(lines)
        super(lines)
        @type = "function"

        @human_name = SILFunctionComment.new(lines[0][:value])
        @definition = SILFunctionDefinition.new(lines[1][:value])
        @building_blocks = parse_building_blocks(lines.drop(2)[0...-1])
        @end = lines.last
      end
      def print(output)
        @human_name.print(output)
        @definition.print(output)
        @building_blocks.each {|x| x.print(output)}
        output.print(@end)
        output.puts ""
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
      def initialize(line)
        super([line])
        @type = "function_comment"
        @name = [/\/\/\s(.*)/, 1]
      end
    end

    class SILFunctionDefinition < SILBlock
      def initialize(line)
        super([line])
        @type = "function_definition"

        parsed_tokens = []
        function = {}
        @isExternal = false

        return_string_index_start = 0
        tokens = line.split(' ')
        tokens.each_with_index do |token, index| 
          if token.start_with?("$@convention")
            parsed_tokens.append({type:"convention", value:token[/$@convention\(.*\)/, 1]})
            return_string_index_start = index
          elsif token == "sil"
            ## skip
            parsed_tokens.append({type:"sil", value:token})
          elsif token.start_with?("[")
            parsed_tokens.append({type:"attribute", value:token[/[(.*)]]/, 1]})
          elsif token == ":"
            parsed_tokens.append({type:"separator", value:token})
          elsif token.start_with?("@$")
            parsed_tokens.append({type:"name", value:token})
          elsif token.start_with?("->")
            parsed_tokens.append({type:"return", value:token})
          elsif token.end_with?("_external")
            @isExternal = true
            parsed_tokens.append({type:"external", value:token})
          elsif token.end_with?("{")
            parsed_tokens.append({type:"finish", value:token})
          else
            parsed_tokens.append({type:"other", value:token})
          end
        end
        return_string = parsed_tokens.drop(return_string_index_start + 1)[0...-1].map{|x| x[:value]}.join(" ")
        @return_type = parse_return_type(read_return_type(return_string))
        return function
      end
      private def optional_wrapper
        return @return_type[/^Optional<(.*)>$/, 1]
      end 
      private def optional_nofunction_wrapper
        return @return_type[/^Optional<(((?!->).)*)>$/, 1]
      end 
      private def parse_return_type(return_type)
        return return_type.gsub(/@\S*\s/,'')
      end
      private def read_return_type(return_definition)
        return_began = false
        brackets_level = 0
        returnTypeChars = []
        chars = return_definition.split("")
        chars.zip(chars.drop(1)).each do |c,n|
          if return_began
            returnTypeChars.append(c)
          elsif c == "("
            brackets_level += 1
          elsif c == ")"
            brackets_level -= 1
          elsif c == "-" && n == ">" && brackets_level == 0
            return_began = true
          end
        end
        # skip "> "
        return returnTypeChars.drop(2).join("")
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
        output.puts(@definition)
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

        # puts parsed
        # @parsed.select {|p| p[:type] == "function"}.map{|f| f[:function][:definition]}.
        # select{|d| !d[:isExternal]}.each {|definition|
        #   puts definition
        # }
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
          elsif parse.type == "function" && !parse.definition.isExternal
            parse.print(output)
=begin
            output.puts parse[:function][:human_name][:value]
            output.puts parse[:function][:definition][:value]
            parse[:function][:building_blocks].each do |bb|
              bb[:comments].each{|x| output.puts x[:value]}
              output.puts bb[:index][:value][:value]
              # not apply for optionals of functions
              if type = parse[:function][:definition][:return_type][/^Optional<(((?!->).)*)>$/, 1]
                arguments = parse[:function][:building_blocks][0][:index][:arguments].size
                output.puts "  %#{arguments} = alloc_stack $Optional<#{type}>              // users: %#{arguments+1}, %#{arguments+3}, %#{arguments+4}"
                output.puts "  inject_enum_addr %#{arguments} : $*Optional<#{type}>, #Optional.none!enumelt // id: %#{arguments+1}"
                output.puts "  %#{arguments+2} = tuple ()"
                output.puts "  %#{arguments+3} = load %#{arguments} : $*Optional<#{type}>               // user: %#{arguments+5}"
                output.puts "  dealloc_stack %#{arguments} : $*Optional<#{type}>           // id: %#{arguments+4}"
                output.puts "  return %#{arguments+3} : $Optional<#{type}>                   // id: %#{arguments+5}"
                break
              end
              bb[:value].map{|x| output.puts x[:value]}
            end
            output.puts parse[:function][:end][:value]
            output.puts ""
          elsif parse[:type] == "function"
            ## copy immediatelly
            parse[:function][:lines].each{|x| output.puts x[:value]}
            output.puts ""
=end
          end

        end
      end


      def parse(tokens)
        parsed = []
        index = 0
        nextFunction = SILBlock.find_index("function_body_start", tokens, index).to_i - 1
        until nextFunction > 0
          if nextFunction  > (index + 2) 
            # parsed.append({type:"static", lines:tokens[index..(nextFunction-2)]})
            parsed.append(SILBlock.new(tokens[index..(nextFunction-2)]))
          end
          #parsed.append({type:"function", function:parse_next_function(tokens, nextFunction - 1)})
          index = SILBlock.find_index("end", tokens, nextFunction)
          parsed.append(SILFunction.new(tokens[nextFunction...index]))

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
