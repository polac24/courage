class VersionCommand < Clamp::Command

  def execute
    puts "courage #{Courage::VERSION}"
  end
end
