require "test_helper"

class WargCommandTest < Minitest::Test
  def test_defining_parser_options
    # See dummy/commands/top.rb
    runner = Warg::Runner.new %w( top -u toby -t localhost )
    runner.run

    context = runner.context

    assert_equal "toby", context.top.user
    assert_equal ["ssh://localhost"], context.hosts.map(&:to_s)
  end

  def test_chaining_commands
    # See dummy/commands/chaining.rb
    runner = Warg::Runner.new %w( chaining )

    context = runner.context
    context.variables(:chain_example) do |chain_example|
      chain_example.deposits = []
    end

    runner.run

    # See `Chaining#call`
    assert_equal %w( first second first second first first second third ), context.chain_example.deposits
  end

  def test_reporting_steps_run_locally
    # See dummy/commands/local_user.rb
    runner = Warg::Runner.new %w( local-user )
    runner.run

    assert_equal ENV["USER"], runner.context.locally.user
  end

  def test_capturing_errors_in_code_run_locally
    # See dummy/commands/broken.rb
    runner = Warg::Runner.new %w( broken )
    runner.run

    context = runner.context

    assert_kind_of RuntimeError, context.locally.failure
    assert_equal "nothing here", context.locally.failure.message
  end

  def test_logs_progress_to_console
    # See dummy/commands/who_we_are.rb
    runner = Warg::Runner.new %w( who-we-are )
    runner.run

    context = runner.context

    assert_equal ENV["USER"], context.log_test.local_user
    assert_equal "warg", context.log_test.remote_user

    assert_includes Warg.console.output, "who-we-are"

    assert_includes Warg.console.output, "local step"
    assert_includes Warg.console.output, "localhost"

    assert_includes Warg.console.output, "whoami"
    assert_includes Warg.console.output, "warg-testing"
  end

  def test_chaining_commands_dynamically
    # See dummy/commands/dynamic_chaining.rb
    runner = Warg::Runner.new %w( dynamic-chaining )
    runner.run

    local_user_index = Warg.console.output.index("local-user")
    who_we_are_index = Warg.console.output.index("who-we-are")

    assert local_user_index
    assert who_we_are_index

    assert local_user_index < who_we_are_index
  end
end
