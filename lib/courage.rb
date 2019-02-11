# Copyright (c) 2019 Bartosz Polaczyk
# Distributed under the MIT License

require "courage/version"
require "courage/command/courage_action"

module Courage
  DEFAULT_LEVEL=100

  def self.courage(options)
    courage = Actions::CourageAction.run(options)
  end
end
