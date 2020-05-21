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
end
