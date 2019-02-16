

module Courage

  module Mutation
  	class FunctionMutation
      def self.isSupported(function, allowed_symbols)
        return false unless function.type == "function"
        return false if !allowed_symbols.include?(function.definition.name)
        return true
      end
    end

  end
end