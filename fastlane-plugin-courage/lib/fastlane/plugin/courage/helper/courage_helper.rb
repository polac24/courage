require 'fastlane_core/ui/ui'

module Fastlane
  UI = FastlaneCore::UI unless Fastlane.const_defined?("UI")

  module Helper
    class SILParser
      # class methods that you define here become available in your action
      # as `Helper::SILParser.your_method`
      #
      def initialize(path)
        @path = path

        tokens = tokenize(path)
        parsed = parse(tokens)

        # puts parsed
        # parsed.select {|p| p[:type] == "function"}.map{|f| f[:function][:definition]}.
        # select{|d| !d[:isExternal]}.each {|definition|
        #   puts definition
        # }

        parsed.each do  |parse|
          if parse[:type] == "static"
            parse[:lines].map{|x| puts x[:value]}
          elsif parse[:type] == "function"
            puts parse[:function][:human_name][:value]
            puts parse[:function][:definition][:value]
            parse[:function][:building_blocks].each do |bb|
              bb[:comments].each{|x| puts x[:value]}
              puts bb[:index][:value][:value]
              bb[:value].map{|x| puts x[:value]}
            end
            puts parse[:function][:end][:value]
          end 
        end
      end


      def parse(tokens)
        parsed = []
        index = 0
        nextFunction = find_index("function_body_start", tokens, index)
        until nextFunction.nil?
          if nextFunction  > (index + 2) 
            parsed.append({type:"static", lines:tokens[index..(nextFunction-2)]})
          end
          parsed.append({type:"function", function:parse_next_function(tokens, nextFunction)})
          index = find_index("end", tokens, nextFunction) + 1
          nextFunction = find_index("function_body_start", tokens, index)
        end
        #rest of static
        parsed.append({type:"static", lines:tokens.drop(index)})
      end


      def parse_next_function(tokens, start_index)
        end_index = find_index("end", tokens, start_index)

        return parse_function(tokens, start_index, end_index)
      end

      def find_index(type, tokens, fromIndex)
        i = tokens.drop(fromIndex).index { |token| token[:type] == type} 
        if i.nil?
          return nil
        end
        return i + fromIndex
      end

      def find_last_index(type, tokens)
        return reversed_index = tokens.rindex { |token| token[:type] == type}
      end


      def parse_function(tokens, start, stop)
        function = {}


        function[:human_name] = parse_function_name(tokens[start-1])
        function[:definition] = parse_function_definition(tokens[start])
        function[:building_blocks] = parse_building_blocks(tokens[(start+1)..(stop-1)])
        function[:end] = tokens[stop]
        function[:lines] = tokens
        return function
      end

      def parse_function_name(line)
        return {name: line[:value][/\/\/\s(.*)/, 1], value:line[:value]}
      end
      def parse_function_definition(line)
        parsed_tokens = []
        function = {}

        tokens = line[:value].split(' ')
        tokens.each do |token| 
          if token.start_with?("$@convention")
            parsed_tokens.append({type:"convention", value:token[/$@convention\(.*\)/, 1]})
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
            parsed_tokens.append({type:"external", value:token})
          elsif token.end_with?("{")
            parsed_tokens.append({type:"finish", value:token})
          else
            parsed_tokens.append({type:"other", value:token})
          end
        end

        function[:isExternal] = !find_index("external",parsed_tokens,0).nil?
        return_string_index_start = find_index("convention", parsed_tokens, 0)
        return_string = parsed_tokens.drop(return_string_index_start + 1).reverse.drop(1).reverse.map{|x| x[:value]}.join(" ")
        function[:return_type] = parse_return_type(read_return_type(return_string))
        function[:value]  = line[:value]
        return function
      end

      def parse_building_blocks(lines)
        parsed_blocks = []
        index = 0
        while index < (lines.count-1) do
          end_bb = find_index("empty",lines, index) || (lines.count-1)
          parsed_blocks.append(parse_building_block(lines[index..end_bb]))
          index = end_bb + 1
        end
        parsed_blocks
      end
      def parse_building_block(lines)
        block = {}

        definition_index = find_index("bb_start", lines, 0)
        block[:index] = parse_block_number(lines[definition_index])
        block[:comments] = lines.first(definition_index)
        block[:value] = lines.drop(definition_index+1)
        return block
      end
      def parse_block_number(line)
        return {index:line[:value][/bb(\d*)\(/, 1], value:line}
      end
      def read_return_type(return_definition)
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
      def parse_return_type(return_type)
        slimed_return_type = return_type.gsub(/@\S*\s/,'')
        return slimed_return_type
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
