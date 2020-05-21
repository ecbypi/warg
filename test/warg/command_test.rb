require "test_helper"

class WargCommandTest < Minitest::Test
  def test_defining_parser_options
    top_command = Class.new do
      include Warg::Command::Behavior

      def run
      end

      def configure_parser!
        @context.parser.on("-u USER", "user to filter processes for") do |user|
          @context.variables(:top) do |top|
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

      def run
        @context.chain_example.deposits << "first"
      end
    end

    second_command = Class.new do
      include Warg::Command::Behavior

      def run
        @context.chain_example.deposits << "second"
      end
    end

    third_command = Class.new do
      include Warg::Command::Behavior

      def run
        # NOTE: `chain_example.other_commands` is only necessary because we can't access
        # `first_command` and `second_command` in the `run` method
        chain(*@context.chain_example.other_commands)

        @context.chain_example.deposits << "third"
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
end
