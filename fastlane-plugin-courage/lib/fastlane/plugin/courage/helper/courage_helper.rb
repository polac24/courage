require 'fastlane_core/ui/ui'
require_relative 'courage_helper_types'
require_relative 'courage_helper_blocks'
require_relative 'courage_helper_mutations'

module Fastlane
  UI = FastlaneCore::UI unless Fastlane.const_defined?("UI")

  module Helper
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

      def parsed 
        @parsed
      end

      def print(output)
        @parsed.each do  |parse|
          parse.print(output)
        end
      end


      def parse(tokens)
        parsed = []
        index = 0
        nextFunction = SILBlock.find_index("function_body_start", tokens, index).to_i - 1
        while nextFunction > 0
          if nextFunction  > (index + 1) 
            parsed.append(SILBlock.new(tokens[index..(nextFunction-1)]))
          end
          index = SILBlock.find_index("end", tokens, nextFunction)+1
          parsed.append(SILFunction.new(tokens[nextFunction...(index)]))

          nextFunction = SILBlock.find_index("function_body_start", tokens, index).to_i - 1
        end
        #rest of a static
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
