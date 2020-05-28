require "test_helper"

class WargRunnerTest < Minitest::Test
  def test_loading_config_and_code_and_running_command
    runner = Warg::Runner.new %w( uptime -h warg@warg-testing )

    stdout, _ = capture_io do
      runner.run
    end

    # Settings from config in `spec/dummy`
    assert_equal ENV["USER"], Warg.default_user

    # Configuration in `config/app.rb`
    assert_equal "muchi", Warg.config.app.name
    assert_equal "muchi", Warg.config.app.user

    # Check `spec/dummy` is added to the search paths
    assert_includes Warg.search_paths, Warg::Testing.dummy_directory

    # this checks that commands and scripts were loaded
    #
    # see `Uptime` command in `spec/dummy/warg/commands`
    assert defined?(Uptime)
    assert defined?(ProcessSnapshot)

    assert_match(/\d+:\d+:\d+\s+up/, stdout)
  end

  def test_prints_to_stderr_and_exits_when_command_isnt_found
    runner = Warg::Runner.new %w( downtime -h localhost )

    _, stderr = capture_io do
      begin
        runner.run
      rescue SystemExit
      end
    end

    assert_equal %{Could not find command from ["downtime", "-h", "localhost"]\n}, stderr
  end

  def test_autoloads_scripts_as_commands
    Warg.configure do |config|
      config.variables(:top) do |top|
        top.user = "warg"
      end
    end

    runner = Warg::Runner.new %w( process-snapshot -h warg@nuba-nuba )
    ProcessSnapshot.extend(Warg::Testing::CaptureStdout)

    stdout, _ = capture_io do
      runner.run
    end

    assert_match(/top - \d+:\d+:\d+\s+up/, stdout)
    assert_match(/^\s*\d+\s+warg/, stdout)
  end
end
