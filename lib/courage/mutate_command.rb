class MutateCommand < Clamp::Command
  parameter "[PROJECT]", "Path to the .xcodeproj", :attribute_name => :xcodeproj_path

  option ["--format"], "FORMAT", "Type of output format (json, console)"

  def execute
    xcodeproj_path_to_open = xcodeproj_path || Courage::Project.yml["xcodeproj"]
    unless xcodeproj_path_to_open
      raise StandardError, "Must provide a .xcodeproj either via the 'courage [SUBCOMMAND] [PROJECT].xcodeproj' command or through .courage.yml"
    end
  end
end
