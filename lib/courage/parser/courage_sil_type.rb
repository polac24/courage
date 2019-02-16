
module Courage

  module Parser
    class Type
      def self.build(type)
        type = type.strip
        if match = type.match(/^(.*).Type$/)
          type = match.captures
          return TypeType.new(type)
        end
        if match = type.match(/^([^<]*)<(.*)>$/)
          type, generic = match.captures
          return Generic.new(type,generic)
        end
        if match = self.read_function_type(type)
          argument, return_type = match
          return Closure.new(argument,return_type)
        end
        return SimpleType.new(type)
      end
      def self.read_function_type(return_definition)
        brackets_level = 0
        chars = return_definition.split("")
        function_separator_index = chars.zip(chars.drop(1)).index{ |c,n|
          if c == "("
            brackets_level += 1
          elsif c == ")"
            brackets_level -= 1
          elsif c == "-" && n == ">" && brackets_level == 0
            next true
          end
          false
        }
        return nil unless function_separator_index
        argument_type = return_definition[0..function_separator_index-1]
        return_type = return_definition[function_separator_index + 3..-1]
        return argument_type, return_type
      end
      def initialize(name)
        @type = name
      end
      def type
        @type
      end
      def isSimpleType
        return false
      end
      def isGeneric
        return false
      end
      def isClosure
        return false
      end
      def isType
        return false
      end
      def to_s
        @type
      end
    end

    class SimpleType < Type
      def isSimpleType
        return true
      end
    end

    class Generic < Type
      def initialize(name,genericString)
        @type = Type.build(name)
        @generics = genericString.split(",").map{|x| Type.build(x)}
      end
      def type
        return @type
      end
      def generics
        return @generics
      end
      def isGeneric
        return true
      end
      def hasGenericClosure
        @generics.any? {|x| x.isClosure}
      end
      def to_s
        generics = @generics.join(",")
        "#{@type}<#{generics}>"
      end
    end
    class Closure < Type
      def initialize(arguments,return_type)
        @arguments = Type.build(arguments)
        @return_type = Type.build(return_type)
      end
      def isClosure
        return true
      end
      def to_s
        "#{@arguments}->#{@return_type}"
      end
    end
    class TypeType < Type
      def initialize(name)
        @typeType = name
      end
      def isType
        return true
      end
      def to_s
        "#{@typeType}.Type"
      end
    end
  end
end
