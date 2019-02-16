module Courage
  module Build

  	class XcodeBuild
  		def initialize(project: nil, workspace: nil, scheme: nil, device: nil)
  			  @project = "-project #{project}"
	        @project = "-workspace #{workspace}" if workspace
	        @command = "xcodebuild clean build-for-testing #{@project} -scheme #{scheme} -destination 'platform=iOS Simulator,name=#{device}'"
  		end

  		def build (parser: nil, verbose: false) 
	      Core::CommandExecutor.execute(command: @command,
                      print_all: true,
                  print_command: verbose,
                         prefix: parser.output_prefix(),
                        loading: "Building project...",
                          error: proc do |error_output|
                            puts error_output
                            asd
                          end)
  		end
  	end

  	class XcodeBuildParser
      def initialize(target: nil, verbose: false)
      	@all_build_commands = []
      	@buildCommandsStack = []
        @linkCommand = nil
        @target = target
        @verbose = verbose
        @fileLists = {}
      end
      def all_build_commands()
      	# First retrival for commands - move from buildCommandsStack
	    if !@buildCommandsStack.empty?
	        all_builds.push(@buildCommandsStack)
	        @buildCommandsStack = []
	    end
        @all_build_commands
      end
      def linkCommand()
        @linkCommand
      end
      def fileLists()
        @fileLists
      end

      def output_prefix () 
      	targetName = ""
    		enabledTarget = true
    		linkGroup = false
    		compileGroup = false

      	[{
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
              if !@buildCommandsStack.empty?
                @all_build_commands.push(@buildCommandsStack)
                @buildCommandsStack = []
              end
              targetName = targetMatcher.call(value)
              enabledTarget = (value.include?("=== BUILD TARGET #{@target}") || targetName == @target)
              linkGroup = false
            end
            if value.to_s.empty? 
              compileGroup = false
            elsif value.include?("XCTest.framework")
              enabledTarget = false
            elsif value.include?("CompileSwift")
              compileGroup = true
            elsif compileGroup && value.include?("/swift ") && enabledTarget
              # copy fileList into a local file (immediatelly)
              if fileList = value[/\s\-filelist\s(\S+)/,1] 
                if @fileLists["#{fileList}"].nil?
                  copiedFileListsPath = "#{fileList}_"
                  Core::CommandExecutor.execute(command: "cp -r #{fileList} #{copiedFileListsPath}")
                  @fileLists["#{fileList}"] = copiedFileListsPath
                end
              end
              value = fileLists.reduce(value) {|prevValue,(key, value)| prevValue.gsub(key, value)}
              @buildCommandsStack.push(value)
            elsif value.include?("Ld")
              linkGroup = true
            elsif linkGroup && value.include?("/clang ") && enabledTarget
              @linkCommand = value
              linkGroup = false
            end
          end
        }]
      end
    end
  end
end