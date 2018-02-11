require 'fastlane/action'
require_relative '../helper/courage_helper'

module Fastlane
  module Actions
    class CourageAction < Action
      def self.run(params)
        UI.message("The courage plugin is working!")
        start_device(device:params[:device])
        command = "xcodebuild clean build-for-testing -project #{params[:project]} -scheme #{params[:scheme]} -destination 'platform=iOS Simulator,name=#{params[:device]}'"

        buildCommands = []
        linkCommand = nil

        compileGroup = false
        linkGroup = false
        enabledTarget = true

        prefix_hash = [
        {
          prefix: "",
          block: proc do |value|

            if value.start_with?("=== BUILD TARGET")
              enabledTarget = true
              linkGroup = false
            end

            if value.to_s.empty? 
              compileGroup = false
            elsif value.include?("XCTest.framework")
              enabledTarget = false
            elsif value.include?("CompileSwift")
              compileGroup = true
            elsif compileGroup && value.include?("/swift ") && enabledTarget
              buildCommands.push(value)
            elsif value.include?("Ld")
              linkGroup = true
            elsif linkGroup && value.include?("/clang ") && enabledTarget
              linkCommand = value
              linkGroup = false
            end

          end
        }
      ]

              FastlaneCore::CommandExecutor.execute(command: command,
                                          print_all: true,
                                      print_command: true,
                                             prefix: prefix_hash,
                                            loading: "Loading...",
                                              error: proc do |error_output|
                                                begin
                                                  exit_status = $?.exitstatus
                                                  ErrorHandler.handle_build_error(error_output)
                                                rescue => ex
                                                  SlackPoster.new.run({
                                                    build_errors: 1
                                                  })
                                                  raise ex
                                                end
                                              end)
              files = make_sibs(commands:buildCommands, linkCommand: linkCommand)

              start_mutations(files:files, params: params)
      end

      def self.make_sibs(commands:commands, linkCommand: linkCommand)
        files = []
        commands.each do |element|
          compilingFile = element[/\s-primary-file\s(.*?\.swift)/,1]
          oFile = element[/\s-o\s(.*?[^\\])\s/,1]
          command = element.gsub(/-emit-module-path.*\.swiftmodule /, ' ').gsub('.o ', '.sib ') + " -emit-sib"
          sibFile = command[/\s-o\s(.*?[^\\])\s/,1]
          files.push({sibPath:sibFile, command: element, compilingFile:compilingFile, linkCommand: linkCommand, oFile:oFile})
          FastlaneCore::CommandExecutor.execute(command: command,
                                          print_all: false,
                                      print_command: true)

        end
        make_sils(files:files)
        prepare_sils(files:files)
      end

      def self.make_sils(files:files)
        files.each_with_index do |element, index|
          command = element[:command].gsub('.o ', '.sil ') + " -emit-sil "
          FastlaneCore::CommandExecutor.execute(command: command,
                                          print_all: false,
                                      print_command: true)
        end
      end

      def self.prepare_sils(files:files)
        totalFiles = []
        files.each_with_index do |element, index|
          other_files = (files.first(index) + files.drop(index+1))
          all_sibs = other_files.reduce("") {|prev,file| prev+file[:sibPath]+" "}
          sil = element[:sibPath].gsub('.sib', '.sil')
          sil_mutated = sil.sub('.sil', '_.sil')
          `echo "sil_stage canonical" >> #{sil_mutated}`
          `cat #{element[:compilingFile]} >> #{sil_mutated}`
          `tail -n +2 #{sil} >> #{sil_mutated}`
          command = element[:command].gsub(/\s(\S*?\.swift)/, ' ').sub(' -primary-file ',' ') + " #{all_sibs} -primary-file #{sil_mutated}"
      
          file = {sibPaths:all_sibs, rebuildCommand:command, originalSil: sil, mutationSill: sil_mutated, linkCommand: element[:linkCommand], oFile:element[:oFile]}
          totalFiles.push(file)
        end
        totalFiles
      end

      def self.start_mutations(files:files, params:params)
        files.reverse_each do |file|
          command = file[:rebuildCommand]
          linkCommand = file[:linkCommand]
          output = file[:oFile]
          `mv #{output} #{output}_`
          # Mutate - TD

          # Build after mutation
          FastlaneCore::CommandExecutor.execute(command: command,
                                          print_all: true,
                                      print_command: true)

          # Link after mutation
          FastlaneCore::CommandExecutor.execute(command: linkCommand,
                                          print_all: true,
                                      print_command: true)

          test_command = "xcodebuild test-without-building -project #{params[:project]} -scheme #{params[:scheme]} -destination 'platform=iOS Simulator,name=#{params[:device]}'"
          FastlaneCore::CommandExecutor.execute(command: test_command,
                                          print_all: false,
                                      print_command: false,
                                      error: proc do |error_output|
                                        begin
                                          rescue => ex
                                        end
                                        end)
          `mv #{output}_ #{output}`
        end
      end

      def self.start_device(device:device)
        FastlaneCore::CommandExecutor.execute(command: "xcrun simctl boot \"#{device}\"",
                                          print_all: false,
                                      print_command: false,
                                      loading: "Starting simulator...",
                                      error: proc do |error_output|
                                        begin
                                          rescue => ex
                                        end
                                        end
                                      )
      end

      def self.description
        "Mutation tests for iOS"
      end

      def self.authors
        ["Bartosz Polaczyk"]
      end

      def self.return_value
        # If your method provides a return value, you can describe here what it does
      end

      def self.details
        # Optional:
        "Evaluate quality of your tests by mutation tests of your swift implementation"
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :project,
                                  env_name: "COURAGE_YOUR_OPTION",
                               description: "A description of your option",
                                  optional: false,
                                      type: String),
          FastlaneCore::ConfigItem.new(key: :scheme,
                                  env_name: "COURAGE_YOUR_OPTION",
                               description: "A description of your option",
                                  optional: false,
                                      type: String),
          FastlaneCore::ConfigItem.new(key: :device,
                                  env_name: "COURAGE_YOUR_OPTION",
                               description: "A description of your option",
                                  optional: false,
                                      type: String)
        ]
      end

      def self.is_supported?(platform)
        # Adjust this if your plugin only works for a particular platform (iOS vs. Android, for example)
        # See: https://docs.fastlane.tools/advanced/#control-configuration-by-lane-and-by-platform
        #
        # [:ios, :mac, :android].include?(platform)
        true
      end
    end
  end
end
