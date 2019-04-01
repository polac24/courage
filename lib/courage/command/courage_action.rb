require_relative '../build/courage_build'
require_relative '../parser/courage_parser'
require_relative '../mutation/courage_sil_mutation'
require_relative '../ui/ui'
require_relative '../commands/command_executor'


module Courage
  module Actions
    class CourageAction 
      def self.run(params)
        fileLists = {}

        if  params[:sil_file] 
          # Parser::SILParser.new(params[:sil_file]).print($stdout)
          allowed_symbols = Parser::SILParser.new(params[:sil_file].gsub(/\.sil/, '_profiles.sil')).explicit_symbols
          parsed = Parser::SILParser.new(params[:sil_file])
          puts parsed.explicit_symbols

          mutations = Mutation::SILMutations.new(parsed.parsed, allowed_symbols)
          puts mutations.mutationsCount
          mutations.print_mutation(0, $stdout)
          return 
        end

        verbose = params[:verbose] 


        start_device(params[:device], verbose)
        build_parser = Build::XcodeBuildParser.new(targets: params[:targets], verbose: verbose)
        xcode_builder = Build::XcodeBuild.new(project: params[:project], workspace: params[:workspace], scheme: params[:scheme], device: params[:device])
        xcode_builder.build(parser: build_parser, verbose: verbose)
        fileLists = build_parser.fileLists
        
      UI.message("Project scanning...")

      linkCommand = build_parser.linkCommand()
      files = []
      build_parser.all_build_commands.each {|buildCommands|
        command_files = make_sibs(commands:buildCommands.reverse, linkCommand: linkCommand, verbose: verbose)
        files.push(*command_files)     
      }
      start_mutations(files:files, params: params, verbose: verbose)
      ensure
        # remove temprary -filelist copies
        fileLists.each do |origianal_path, copied_path|
          Core::CommandExecutor.execute(command: "rm #{copied_path}")
        end
      end

      def self.make_sibs(commands: nil, linkCommand: nil, verbose: false)
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
          Core::CommandExecutor.execute(command: command,
                                          print_all: true,
                                      print_command: verbose)

        end
        make_sils(files:files, verbose: verbose)
        prepare_sils(files:files)
      end

      def self.make_sils(files: nil, verbose: false)
        files.each_with_index do |element, index|
          command = element[:command].gsub('.o', '.sil') + " -emit-sil "
          Core::CommandExecutor.execute(command: command,
                                          print_all: false,
                                      print_command: verbose)

          # include 
          command = element[:command].gsub('.o', '_profiles.sil') + " -emit-sil -profile-coverage-mapping -profile-generate"
          Core::CommandExecutor.execute(command: command,
                                          print_all: false,
                                      print_command: verbose)
        end
      end

      def self.prepare_sils(files: nil, verbose: false)
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

      def self.start_mutations(files: nil, params: nil, verbose: false)
          mutation_succeeded = []   
          mutation_failed = []                        
          mutation_skipped = []     

          # TODO: optimize searching for mutations
          total_mutations = files.reverse.inject([]) {|prev, file|
            allowed_symbols = Parser::SILParser.new(file[:sil_with_profiles]).explicit_symbols
            parsed = Parser::SILParser.new(file[:sil_reference])
            parsedBlocks = parsed.parsed
            mutations = Mutation::SILMutations.new(parsedBlocks, allowed_symbols)
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
          allowed_symbols = Parser::SILParser.new(file[:sil_with_profiles]).explicit_symbols
          parsed = Parser::SILParser.new(file[:sil_reference])
          parsedBlocks = parsed.parsed
          mutations = Mutation::SILMutations.new(parsedBlocks, allowed_symbols)

          

          if mutations.mutationsCount > 0
            # ensure no-mutation sil suceeds
            parsed.printToFile(file[:mutationSill])
            #UI.message("Mutations for file: #{file[:originalSil]}")

            if rebuild_and_test(command:command, linkCommand:linkCommand, params:params, verbose: verbose) != true
              #mutation cannot be built from .sil
               mutation_skipped.push("Unsupported file: #{file[:compilingFile]}")
               UI.important("File ineligable for mutation: #{file[:compilingFile]}")
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
        UI.message("-----------")
        UI.message("Succeeded:")
        UI.message("#{mutation_succeeded}")
        UI.message("Failed:")
        UI.message("#{mutation_failed}")
        UI.message("Skipped:")
        UI.message("#{mutation_skipped}")
        UI.message("-----------")
        successes = mutation_succeeded.count
        failures = mutation_failed.count
        if successes + failures == 0
          UI.important("Tests quality: 0%")
        else
          UI.important("Tests quality: #{successes*100/(successes+failures)}% (#{successes}/#{successes+failures})")
        end

      end

      def self.start_device(device , verbose)
        Core::CommandExecutor.execute(command: "xcrun simctl boot \"#{device}\"",
                                          print_all: true,
                                      print_command: verbose,
                                      loading: "Starting simulator...",
                                      error: proc do |error_output|
                                        begin
                                          rescue => ex
                                        end
                                        end,
                                      suppress_output: true
                                      )
      end

      def self.rebuild_and_test(command: nil, linkCommand: nil, params: nil, verbose: false)
        begin
          # Build after mutation
          Core::CommandExecutor.execute(command: "#{command} &> /dev/null",
                                          print_all: true,
                                      print_command: verbose
                                      )

          # Link after mutation
          Core::CommandExecutor.execute(command: "#{linkCommand} &> /dev/null",
                                          print_all: true,
                                      print_command: verbose
                                      )


          project = "-project #{params[:project]}"
          project = "-workspace #{params[:workspace]}" if params[:workspace]

          test_command = "expect -c \"spawn xcodebuild test-without-building #{project} -scheme #{params[:scheme]} -parallel-testing-enabled NO -destination \\\"platform=iOS Simulator,name=#{params[:device]}\\\"; expect -re \\\"Fatal error:|'\sfailed\\\.|Terminating\sapp\sdue\\\" {exit 1} \" &> /dev/null "
          begin
            Core::CommandExecutor.execute(command: test_command,
                                            print_all: true,
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
        true
      end
    end
  end
end
