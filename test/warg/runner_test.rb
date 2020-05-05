require "test_helper"

class WargRunnerTest < Minitest::Test
  def test_loading_config_and_code_and_running_command
    dummy_warg_directory = File.expand_path(File.join("..", "dummy", "warg"), __dir__)
    Dir.chdir dummy_warg_directory

    runner = Warg::Runner.new %w( uptime -h localhost )
    stdout, _ = capture_io do
      runner.run
    end

    # Settings from config in `spec/dummy`
    assert_equal ENV["USER"], Warg.default_user

    # Check `spec/dummy` is added to the search paths
    assert_includes Warg.search_paths, Pathname.new(dummy_warg_directory)

    # this checks that commands and scripts were loaded
    #
    # see `Uptime` command in `spec/dummy/warg/commands`
    assert defined?(Uptime)

    assert_match(/\d+:\d+(?::\d+)?\s+up/, stdout)
  end

  def test_raises_when_command_isnt_found
    dummy_warg_directory = File.expand_path(File.join("..", "dummy", "warg"), __dir__)
    Dir.chdir dummy_warg_directory

    runner = Warg::Runner.new %w( downtime -h localhost )

    assert_raises(RuntimeError) { runner.run }
  end
end
