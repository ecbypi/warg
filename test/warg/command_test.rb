require "test_helper"

class WargCommandTest < Minitest::Test
  def test_defining_parser_options
    top_command = Class.new do
      include Warg::Command::Behavior
      @command_name = Warg::Command::Name.new(script_name: "top")

      def run
      end

      def configure_parser!
        parser.on("-u USER", "user to filter processes for") do |user|
          context.variables(:top) do |top|
            top.user = user
          end
        end
      end
    end

    context = Warg::Context.new %w( top -u toby -h localhost )

    top_command.(context)

    assert_equal "toby", context.top.user
    assert_equal ["ssh://localhost"], context.hosts.map(&:to_s)
  end

  def test_chaining_commands
    first_command = Class.new do
      include Warg::Command::Behavior
      @command_name = Warg::Command::Name.new(script_name: "first")

      def run
        context.chain_example.deposits << "first"
      end
    end

    second_command = Class.new do
      include Warg::Command::Behavior
      @command_name = Warg::Command::Name.new(script_name: "second")

      def run
        context.chain_example.deposits << "second"
      end
    end

    third_command = Class.new do
      include Warg::Command::Behavior
      @command_name = Warg::Command::Name.new(script_name: "third")

      def run
        # NOTE: `chain_example.other_commands` is only necessary because we can't access
        # `first_command` and `second_command` in the `run` method
        chain(*context.chain_example.other_commands)

        context.chain_example.deposits << "third"
      end
    end

    combined_command = first_command | second_command | first_command

    context = Warg::Context.new([])
    context.variables(:chain_example) do |chain_example|
      chain_example.deposits = []
      chain_example.other_commands = [first_command, second_command]
    end

    _ = first_command.(context) | second_command

    assert_equal %w( first second ), context.chain_example.deposits

    combined_command.(context)

    assert_equal %w( first second first second first ), context.chain_example.deposits

    third_command.(context)

    assert_equal %w( first second first second first first second third ), context.chain_example.deposits
  end

  def test_reporting_steps_run_locally
    localhost_command = Class.new do
      include Warg::Command::Behavior
      @command_name = Warg::Command::Name.new(script_name: "local-user")

      def run
        on_localhost "whoami" do
          context.variables(:locally) do |locally|
            locally.user = `whoami`.chomp
          end
        end
      end
    end

    context = Warg::Context.new %w( local-user )

    localhost_command.(context)

    assert_equal ENV["USER"], context.locally.user
  end

  def test_capturing_errors_in_code_run_locally
    localhost_broken_command = Class.new do
      include Warg::Command::Behavior
      @command_name = Warg::Command::Name.new(script_name: "broke")

      def run
        context.variables(:locally) do |locally|
          locally.failed = false
        end

        on_localhost "whoami" do
          raise "nothing here"
        end
      end

      def on_failure(execution_result)
        outcome = execution_result.value[0]

        context.variables(:locally) do |locally|
          locally.failure = outcome.error
        end
      end
    end

    context = Warg::Context.new %w( broke )

    localhost_broken_command.(context)

    assert_kind_of RuntimeError, context.locally.failure
    assert_equal "nothing here", context.locally.failure.message
  end

  def test_logs_progress_to_console
    log_test_command = Class.new do
      include Warg::Command::Behavior
      @command_name = Warg::Command::Name.new(script_name: "who-we-are")

      def run
        locally "local step" do
          context.variables(:log_test) do |log_test|
            log_test.local_user = `whoami`.chomp
          end
        end

        run_command "whoami", on: Warg::HostCollection.from(["warg-testing"]) do |host, result|
          context.variables(:log_test) do |log_test|
            log_test.remote_user = result.stdout.chomp
          end
        end
      end
    end

    context = Warg::Context.new %w( who-we-are )

    log_test_command.(context)

    assert_equal ENV["USER"], context.log_test.local_user
    assert_equal "warg", context.log_test.remote_user

    assert_includes Warg.console.output, "who-we-are"

    assert_includes Warg.console.output, "local step"
    assert_includes Warg.console.output, "localhost"

    assert_includes Warg.console.output, "whoami"
    assert_includes Warg.console.output, "warg-testing"
  end
end
