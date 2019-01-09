require 'fastlane/action'
require_relative '../helper/courage_helper'

module Fastlane
  module Actions
    class CourageAction < Action
      def self.run(params)

        if  params[:sil_file] 
          #Helper::SILParser.new(params[:sil_file]).print($stdout)
          allowed_symbols = Helper::SILParser.new(params[:sil_file].gsub(/\.sil/, '_profiles.sil')).explicit_symbols
          parsed = Helper::SILParser.new(params[:sil_file])
          puts parsed.explicit_symbols

          mutations = Helper::SILMutations.new(parsed.parsed, allowed_symbols)
          puts mutations.mutationsCount
          mutations.print_mutation(0, $stdout)
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
        targetName = ""
        fileLists = {}
        verbose = params[:verbose] 

        prefix_hash = [
        {
          prefix: "",
          block: proc do |value|

            targetMatcher = lambda { |line| 
              if currentTarget = line[/\s\(in\starget\:\s([^\)]+)\)/, 1] 
                if currentTarget != targetName
                  return currentTarget
                end
              end
              targetName
            }
            # support old & new build system (new build system after "||")
            if value.include?("=== BUILD TARGET") || (targetMatcher.call(value) != targetName)
              if !buildCommands.empty?
                all_builds.push(buildCommands)
                buildCommands = []
              end
              targetName = targetMatcher.call(value)
              enabledTarget = (value.include?("=== BUILD TARGET #{params[:target]}") || targetName == params[:target])
              linkGroup = false
            end


            if value.to_s.empty? 
              compileGroup = false
            elsif value.include?("XCTest.framework")
              enabledTarget = false
            elsif value.include?("CompileSwift")
              compileGroup = true
            elsif compileGroup && value.include?("/swift ") && enabledTarget
              puts value
              # copy fileList into a local file
              if fileList = value[/\s\-filelist\s(\S+)/,1] 
                if fileLists["#{fileList}"].nil?
                  copiedFileListsPath = "#{fileList}_"
                  FastlaneCore::CommandExecutor.execute(command: "cp -r #{fileList} #{copiedFileListsPath}")
                  fileLists["#{fileList}"] = copiedFileListsPath
                end
              end
              value = fileLists.reduce(value) {|prevValue,(key, value)| prevValue.gsub(key, value)}
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
                              print_command: verbose,
                                     prefix: prefix_hash,
                                    loading: "Building project...",
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
        files = make_sibs(commands:buildCommands.reverse, linkCommand: linkCommand, verbose: verbose)

        start_mutations(files:files, params: params, verbose: verbose)
      }
      ensure
        # remove temprary -filelist copies
        fileLists.each do |origianal_path, copied_path|
          FastlaneCore::CommandExecutor.execute(command: "rm #{copied_path}")
        end
      end

      def self.make_sibs(commands:commands, linkCommand: linkCommand, verbose: verbose)
        files = []
        all_swifts = commands.reduce([]) {|prev,file| prev.push(file[/\s-primary-file\s(.*?\.swift|\".*\.swift\")\s/,1])}
        commands.each do |element|
          compilingFile = element[/\s-primary-file\s(.*?\.swift|\".*\.swift\")\s/,1]
          oFile = element[/\s-o\s([^\"].*?[^\\]|\".*?\")\s/,1]

          # filelist prepare: TODO
          element = element.gsub(/\s-filelist\s(\S*?)\s/, ' ')
          element = element.gsub(/\s-primary-file\s(.*?\.swift|\".*\.swift\")\s/, ' ')
          element = element.gsub(/\s-profile-coverage-mapping\s/, ' ')
          element = element.gsub(/\s-profile-generate\s/, ' ')
          element = element.gsub(/\s(\S*?\.swift|\".*\.swift\")\s/, ' ')
          element = all_swifts.reduce(element){ |prev, file| prev.sub(file, ' ') }
          my_swifts = all_swifts - [compilingFile]
          element = element + " -primary-file #{compilingFile} " + my_swifts.reduce(" "){|prev,file| prev + file + " "}



          command = element.gsub(/-emit-module-path.*?\.swiftmodule\"?\s/, ' ').gsub('.o', '.sib') + " -emit-sib"
          sibFile = command[/\s-o\s([^\"].*?[^\\]|\".*?\")\s/,1]
          files.push({sibPath:sibFile, command: element, compilingFile:compilingFile, linkCommand: linkCommand, oFile:oFile})
          FastlaneCore::CommandExecutor.execute(command: command,
                                          print_all: true,
                                      print_command: verbose)

        end
        make_sils(files:files, verbose: verbose)
        prepare_sils(files:files)
      end

      def self.make_sils(files:files, verbose: verbose)
        files.each_with_index do |element, index|
          command = element[:command].gsub('.o', '.sil') + " -emit-sil "
          FastlaneCore::CommandExecutor.execute(command: command,
                                          print_all: false,
                                      print_command: verbose)

          # include 
          command = element[:command].gsub('.o', '_profiles.sil') + " -emit-sil -profile-coverage-mapping -profile-generate"
          FastlaneCore::CommandExecutor.execute(command: command,
                                          print_all: false,
                                      print_command: verbose)
        end
      end

      def self.prepare_sils(files:files, verbose: verbose)
        totalFiles = []
        files.each_with_index do |element, index|
          other_files = (files.first(index) + files.drop(index+1))
          all_sibs = other_files.reduce("") {|prev,file| prev+file[:sibPath]+" "}
          sil = element[:sibPath].gsub('.sib', '.sil')
          sil_mutated = sil.sub('.sil', '_.sil')
          sil_reference = sil.sub('.sil', '_org.sil')
          sil_profiles_reference = sil.sub('.sil', '_profiles.sil')
          # workaround for missing SIL imports
          `grep "import" #{element[:compilingFile]} > #{sil_mutated}`
          `cat #{sil} >> #{sil_mutated}`
          `cp #{sil_mutated} #{sil_reference}`
          command = element[:command].gsub(/\s(\S*?\.swift|\".*\.swift\")/, ' ').sub(' -primary-file ',' ') + " #{all_sibs} -primary-file #{sil_mutated}"
      
          file = {sibPaths:all_sibs, rebuildCommand:command, originalSil: sil, mutationSill: sil_mutated, sil_reference: sil_reference, sil_with_profiles: sil_profiles_reference, linkCommand: element[:linkCommand], oFile:element[:oFile], compilingFile: element[:compilingFile]}
          totalFiles.push(file)
        end
        totalFiles
      end

      def self.start_mutations(files:files, params:params, verbose: verbose)
          mutation_succeeded = []   
          mutation_failed = []                        
          mutation_skipped = []     

          # TODO: optimize searching for mutations
          total_mutations = files.reverse.inject([]) {|prev, file|
            allowed_symbols = Helper::SILParser.new(file[:sil_with_profiles]).explicit_symbols
            parsed = Helper::SILParser.new(file[:sil_reference])
            parsedBlocks = parsed.parsed
            mutations = Helper::SILMutations.new(parsedBlocks, allowed_symbols)
            mutations_count = mutations.mutationsCount
            mutations_names = (0...mutations_count).map{|x| mutations.mutation_name(x)}
            prev+mutations_names
          }

          UI.important("Found #{total_mutations.count} mutations.")
          total_mutations.each_with_index{|x, index| UI.important("#{index+1}. #{x}")}

        files.reverse_each do |file|      

          command = file[:rebuildCommand] + " -assume-parsing-unqualified-ownership-sil"
          linkCommand = file[:linkCommand]
          output = file[:oFile]
          new_output = output.gsub(".o", ".o_")
          `mv #{output} #{new_output}`
          # Mutate - TD
          allowed_symbols = Helper::SILParser.new(file[:sil_with_profiles]).explicit_symbols
          parsed = Helper::SILParser.new(file[:sil_reference])
          parsedBlocks = parsed.parsed
          mutations = Helper::SILMutations.new(parsedBlocks, allowed_symbols)

          

          if mutations.mutationsCount > 0
            # ensure no-mutation sil suceeds
            parsed.printToFile(file[:mutationSill])
            #UI.message("Mutations for file: #{file[:originalSil]}")

            if rebuild_and_test(command:command, linkCommand:linkCommand, params:params, verbose: verbose) != true
              #mutation cannot be built from .sil
               mutation_skipped.push("Unsupported file: #{file[:compilingFile]}")
               UI.error("File ineligable for mutation: #{file[:compilingFile]}")
            else
              # mutation eligable
              for i in 0..(mutations.mutationsCount - 1)
                mutation_name = mutations.print_mutation_to_file(i, file[:mutationSill])
                UI.message("Running mutation: #{mutation_name}...")
                
                test_result = rebuild_and_test(command:command, linkCommand:linkCommand, params:params, verbose: verbose)
                case test_result
                when nil
                  mutation_skipped.push(mutation_name)
                  UI.error("⚠️: Mutation #{mutation_name} cannot be verfied!")
                when true
                  UI.error("🛑 Mutant survived: #{mutation_name}!")
                  mutation_failed.push(mutation_name)
                when false
                  UI.success("✅ Mutation killed: #{mutation_name}!")
                  mutation_succeeded.push(mutation_name)
                end
              end
            end
          end
          `mv #{output}_ #{output}`
        end
        if verbose 
          UI.message("-----------")
          UI.message("Succeeded:")
          UI.message("#{mutation_succeeded}")
          UI.message("Failed:")
          UI.message("#{mutation_failed}")
          UI.message("Skipped:")
          UI.message("#{mutation_skipped}")
          UI.message("-----------")
        end
        successes = mutation_succeeded.count
        failures = mutation_failed.count
        if successes + failures == 0
          UI.important("Tests quality: 0%")
        else
          UI.important("Tests quality: #{successes*100/(successes+failures)}% (#{successes}/#{successes+failures})")
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

      def self.rebuild_and_test(command:command, linkCommand:linkCommand, params:params, verbose: verbose)
        begin
          # Build after mutation
          FastlaneCore::CommandExecutor.execute(command: command,
                                          print_all: verbose,
                                      print_command: verbose
                                      )

          # Link after mutation
          FastlaneCore::CommandExecutor.execute(command: linkCommand,
                                          print_all: verbose,
                                      print_command: verbose
                                      )


          project = "-project #{params[:project]}"
          project = "-workspace #{params[:workspace]}" if params[:workspace]

          test_command = "expect -c \"spawn xcodebuild test-without-building #{project} -scheme #{params[:scheme]} -parallel-testing-enabled NO -destination \\\"platform=iOS Simulator,name=#{params[:device]}\\\"; expect -re \\\"Fatal error:|'\sfailed\\\.|Terminating\sapp\sdue\\\" {exit 1} \" &> /dev/null"
          begin
            FastlaneCore::CommandExecutor.execute(command: test_command,
                                            print_all: false,
                                        print_command: verbose)
            return true
          rescue => testEx
            return false
          end
        rescue => ex
          return nil
        end
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
                                      type: String),
          FastlaneCore::ConfigItem.new(key: :verbose,
                                  env_name: "COURAGE_YOUR_OPTION",
                               description: "A description of your option",
                                  type: Boolean,
                                  default_value: false)
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
