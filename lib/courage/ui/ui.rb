module Courage
  module Actions
  	class UI
  		def self.error(text)
  			puts "Error: #{text}"
  		end
  		def self.message(text)
  			puts "Message: #{text}"
  		end
  		def self.success(text)
  			puts "Success: #{text}"
  		end
  		def self.important(text)
  			puts "Important: #{text}"
  		end
  		def self.command(text)
  			puts "Command: #{text}"
  		end
  	end
  end
end