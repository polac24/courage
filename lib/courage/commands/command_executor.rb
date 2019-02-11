require_relative '../ui/ui'

module Courage
	module Core
		class CommandExecutor
			def self.execute(command: nil, print_all: false, print_command: true, error: nil, prefix: nil, loading: nil, suppress_output: false)
		        prefix ||= {}
		        print_all = true
		        print_command = true

		        output = []
		        command = command.join(" ") if command.kind_of?(Array)
		        Courage::Actions::UI.command(command) if print_command

		        if print_all && loading # this is only used to show the "Loading text"...
		          Courage::Actions::UI.command(loading)
		        end

		        begin
		          status = CouragePty.spawn(command) do |command_stdout, command_stdin, pid|
		            command_stdout.each do |l|
		              line = l.strip # strip so that \n gets removed
		              output << line

		              next unless print_all

		              # Prefix the current line with a string
		              prefix.each do |element|
		                line = element[:prefix] + line if element[:block] && element[:block].call(line)
		              end

		              # Courage::Actions::UI.command_output(line) unless suppress_output
		            end
		          end
		        rescue => ex
		          # FastlanePty adds exit_status on to StandardError so every error will have a status code
		          status = ex.exit_status

		          # This could happen when the environment is wrong:
		          # > invalid byte sequence in US-ASCII (ArgumentError)
		          output << ex.to_s
		          o = output.join("\n")
		          puts(o)
		          if error
		            error.call(o, nil)
		          else
		            raise ex
		          end
		        end

		         # Exit status for build command, should be 0 if build succeeded
		        if status != 0
		          o = output.join("\n")
		          puts(o) unless suppress_output # the user has the right to see the raw output
		          Courage::Actions::UI.error("Exit status: #{status}")
		          if error
		            error.call(o, status)
		          else
		            Courage::Actions::UI.user_error!("Exit status: #{status}")
		          end
		        end

		        return output.join("\n")
		    end
		end

		 class CouragePty
		    def self.spawn(command)
		      require 'pty'
		      PTY.spawn(command) do |command_stdout, command_stdin, pid|
		        begin
		          yield(command_stdout, command_stdin, pid)
		        rescue Errno::EIO
		          # Exception ignored intentionally.
		          # https://stackoverflow.com/questions/10238298/ruby-on-linux-pty-goes-away-without-eof-raises-errnoeio
		          # This is expected on some linux systems, that indicates that the subcommand finished
		          # and we kept trying to read, ignore it
		        ensure
		          begin
		            Process.wait(pid)
		          rescue Errno::ECHILD, PTY::ChildExited
		            # The process might have exited.
		          end
		        end
		      end
		      $?.exitstatus
		    rescue LoadError
		      require 'open3'
		      Open3.popen2e(command) do |command_stdin, command_stdout, p| # note the inversion
		        yield(command_stdout, command_stdin, p.value.pid)

		        command_stdin.close
		        command_stdout.close
		        p.value.exitstatus
		      end
		    rescue StandardError => e
		      raise CouragePty.new(e, $?.exitstatus)
		    end
		  end


		class StandardError
		  def exit_status
		    return -1
		  end
		end

		  class CouragePtyError < StandardError
		    attr_reader :exit_status
		    def initialize(e, exit_status)
		      super(e)
		      set_backtrace(e.backtrace) if e
		      @exit_status = exit_status
		    end
  		  end
	end
end
