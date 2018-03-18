require 'fastlane/action'
require_relative '../helper/courage_helper'

module Fastlane
  module Actions
    class CourageAction < Action
      def self.run(params)

        if  params[:sil_file] 
          #Helper::SILParser.new(params[:sil_file]).print($stdout)
          parsed = Helper::SILParser.new(params[:sil_file]).parsed
          Helper::SILMutations.new(parsed)
          return 
        end
        UI.message("The courage plugin is working!")
        start_device(device:params[:device])
        project = "-project #{params[:project]}"
        project = "-workspace #{params[:workspace]}" if params[:workspace]
        command = "xcodebuild clean build-for-testing #{project} -scheme #{params[:scheme]} -destination 'platform=iOS Simulator,name=#{params[:device]}'"

        all_builds = []
        buildCommands = []
        linkCommand = nil

        compileGroup = false
        linkGroup = false
        enabledTarget = true

        prefix_hash = [
        {
          prefix: "",
          block: proc do |value|

            if value.include?("=== BUILD TARGET")
              if !buildCommands.empty?
                all_builds.push(buildCommands)
                buildCommands = []
              end
              enabledTarget = value.include?("=== BUILD TARGET #{params[:target]}")
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

if !buildCommands.empty?
                all_builds.push(buildCommands)
                buildCommands = []
              end

              all_builds.each {|buildCommands|
                files = make_sibs(commands:buildCommands.reverse, linkCommand: linkCommand)

                start_mutations(files:files, params: params)
              }
      end

      def self.make_sibs(commands:commands, linkCommand: linkCommand)
        files = []
        all_swifts = commands.reduce([]) {|prev,file| prev.push(file[/\s-primary-file\s(.*?\.swift)\s/,1])}
        puts all_swifts
        commands.each do |element|
          compilingFile = element[/\s-primary-file\s(.*?\.swift)\s/,1]
          oFile = element[/\s-o\s(.*?[^\\])\s/,1]

          # filelist prepare: TODO
          element = element.gsub(/\s-filelist\s(\S*?)\s/, ' ')
          element = element.gsub(/\s-primary-file\s(.*?\.swift)\s/, ' ')
          element = element.gsub(/\s-profile-coverage-mapping\s/, ' ')
          element = element.gsub(/\s-profile-generate\s/, ' ')
          element = element.gsub(/\s(\S*?\.swift)\s/, ' ')
          element = all_swifts.reduce(element){ |prev, file| prev.sub(file, ' ') }
          my_swifts = all_swifts - [compilingFile]
          element = element + " -primary-file #{compilingFile} " + my_swifts.reduce(" "){|prev,file| prev + file + " "}



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
          sil_reference = sil.sub('.sil', '_org.sil')
          #`echo "sil_stage canonical" >> #{sil_mutated}`
          #{}`cat #{element[:compilingFile]} >> #{sil_mutated}`
          #{}`tail -n +2 #{sil} >> #{sil_mutated}`
          `grep "import" #{element[:compilingFile]} > #{sil_mutated}`
          `cat #{sil} >> #{sil_mutated}`
          `cp #{sil_mutated} #{sil_reference}`
          command = element[:command].gsub(/\s(\S*?\.swift)/, ' ').sub(' -primary-file ',' ') + " #{all_sibs} -primary-file #{sil_mutated}"
      
          file = {sibPaths:all_sibs, rebuildCommand:command, originalSil: sil, mutationSill: sil_mutated, sil_reference: sil_reference, linkCommand: element[:linkCommand], oFile:element[:oFile]}
          totalFiles.push(file)
        end
        totalFiles
      end

      def self.start_mutations(files:files, params:params)
          mutation_succeeded = []   
          mutation_failed = []                        
          mutation_skipped = []     

        files.reverse_each do |file|      

          command = file[:rebuildCommand] + " -assume-parsing-unqualified-ownership-sil"
          linkCommand = file[:linkCommand]
          output = file[:oFile]
          `mv #{output} #{output}_`
          # Mutate - TD
          # `cp #{file[:sil_reference]}  #{file[:mutationSill]}`
          Helper::SILParser.new(file[:sil_reference]).printToFile(file[:mutationSill])

          begin
          # Build after mutation
          FastlaneCore::CommandExecutor.execute(command: command,
                                          print_all: true,
                                      print_command: true
                                      )

          # Link after mutation
          FastlaneCore::CommandExecutor.execute(command: linkCommand,
                                          print_all: true,
                                      print_command: true
                                      )


        project = "-project #{params[:project]}"
        project = "-workspace #{params[:workspace]}" if params[:workspace]

          #test_command = "xcodebuild test-without-building #{project} -scheme #{params[:scheme]} -destination \"platform=iOS Simulator,name=#{params[:device]}\""
          # any "Fatal error"
          test_command = "expect -c \"spawn xcodebuild test-without-building #{project} -scheme #{params[:scheme]} -destination \\\"platform=iOS Simulator,name=#{params[:device]}\\\"; expect -re \\\"Fatal error:|'\sfailed\\\.|Terminating\sapp\sdue\\\" {exit 1} \" &> /dev/null"
          begin
          FastlaneCore::CommandExecutor.execute(command: test_command,
                                          print_all: false,
                                      print_command: true)
          UI.message("Mutation not caught!")
          mutation_failed.push(file)
            rescue => testEx
              UI.message("Mutation caught!")
              mutation_succeeded.push(file)
            end

         rescue => ex
          mutation_skipped = file
          end
          `mv #{output}_ #{output}`
        end
        UI.message("-----------")
        UI.message("Succeeded:")
        UI.message("#{mutation_succeeded}")
        UI.message("Failed:")
        UI.message("#{mutation_failed.map{|a| a[:sil_reference]}}")
        UI.message("Skipped:")
        UI.message("#{mutation_skipped}")
        UI.message("-----------")
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
                                  optional: true,
                                      type: String),
          FastlaneCore::ConfigItem.new(key: :workspace,
                                  env_name: "COURAGE_YOUR_OPTION",
                               description: "A description of your option",
                                  optional: true,
                                      type: String),
          FastlaneCore::ConfigItem.new(key: :scheme,
                                  env_name: "COURAGE_YOUR_OPTION",
                               description: "A description of your option",
                                  optional: false,
                                      type: String),
          FastlaneCore::ConfigItem.new(key: :target,
                                  env_name: "COURAGE_YOUR_OPTION",
                               description: "A description of your option",
                                  optional: false,
                                      type: String),
          FastlaneCore::ConfigItem.new(key: :device,
                                  env_name: "COURAGE_YOUR_OPTION",
                               description: "A description of your option",
                                  optional: false,
                                      type: String),
          FastlaneCore::ConfigItem.new(key: :sil_file,
                                  env_name: "COURAGE_YOUR_OPTION",
                               description: "A description of your option",
                                  optional: true,
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
