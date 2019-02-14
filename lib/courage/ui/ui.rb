module Courage
  module Actions
  	class UI
  		def self.error(text)
  			puts "#{colorize(text, 31)}"
  		end
  		def self.message(text)
  			puts "#{colorize(text, 39)}"
  		end
  		def self.success(text)
  			puts "#{colorize(text, 32)}"
  		end
  		def self.important(text)
  			puts "#{colorize(text, 33)}"
  		end
  		def self.command(text)
  			puts "#{colorize(text, 36)}"
  		end
  		def self.user_error(text)
  			puts "#{colorize(text, 31)}"
  		end


  		def self.colorize(text, color_code)
		  "\e[#{color_code}m#{text}\e[0m"
		end
  	end
  end
end