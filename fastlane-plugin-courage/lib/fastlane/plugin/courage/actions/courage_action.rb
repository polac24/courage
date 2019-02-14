require 'fastlane/action'
require_relative '../helper/courage_helper'

module Fastlane
  module Actions
    class CourageAction < Action
      def self.run(params)


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
        [:ios].include?(platform)
      end
    end
  end
end
