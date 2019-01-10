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

      def symbols
        @parsed.select{|block|
          block.is_a?(SILFunction) || block.is_a?(SILFunctionHeader) || block.is_a?(SILGlobalVariable)
        }
      end

      def explicit_symbols
        @parsed.select{|block|
          block.is_a?(SILCoverageMap)
        }.inject([]) {|sum, n| sum.append(n.name) }
      end


      def parse(tokens)
        parsed = []
        index = 0
        provider = ContentProvider.new(tokens)
        loop do
          block = SILBlock.nextBlock(provider)
          break if block.nil?
          parsed.append(block)
        end
        parsed
      end

      def tokenize(path)
        number = 0
        tokens = []
        File.readlines(path.gsub("\"",'')).each do |line|
          line = line.chomp
          new_token = {}
          if line.start_with?("sil ") 
            if line.end_with?("{") 
              new_token[:type]="function_body_start"
            else
              new_token[:type]="function_definition"
            end
          elsif line.start_with?("sil_global ")
            new_token[:type]="global_variable"
          elsif line.start_with?("sil_coverage_map ")
            new_token[:type]="coverage_map"
          elsif line.include?(" = begin_access ")
            new_token[:type]="begin_access"
          elsif line.include?(" store ")
            new_token[:type]="store"
          elsif line.start_with?("  return ")
            new_token[:type]="return"
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
    class ContentProvider
      def initialize(tokens)
        @tokens = tokens
        @i = 0
      end
      def peek
        return @tokens[@i]
      end
      def peek_forward
        return @tokens[@i+1]
      end
      def peek_custom(i)
        return @tokens[@i + i]
      end
      def read
        token = @tokens[@i]
        @i += 1
        return token
      end
      def index
        @i
      end
    end
  end
end
