require "simplecov"
SimpleCov.start do
  add_filter %r{^/(?:warg|test)/}
  # For running on ruby 2.3 on CI. Latest simplecov requires ruby 2.4+ and `enable_coverage`
  # only exists on the latest versions
  respond_to?(:enable_coverage) and enable_coverage(:branch)
end

require "byebug"
require "pry"

if ENV["BYEBUG_REMOTE"] == "1"
  require "byebug/core"
  Byebug.wait_connection = true
  Byebug.start_server("localhost", 5000)
end

require "minitest/autorun"
require "minitest/pride"
require "warg"

module Warg
  # Redirect console output to a `StringIO` instance. Prevents disrupting minitest output.
  console.instance_variable_set(:@io, StringIO.new)

  module Testing
    module_function

    VAGRANT_SSH_CONFIG = File.expand_path("ssh_config", __dir__)

    VAGRANT_PRIVATE_KEY = File.expand_path \
      File.join("..", ".vagrant", "machines", "warg-testing", "virtualbox", "private_key"),
      __dir__

    class << self
      attr_accessor :dummy_directory
    end

    self.dummy_directory = Pathname.new File.expand_path(File.join("dummy", "warg"), __dir__)

    def chdir_to_dummy_directory
      Dir.chdir dummy_directory
    end

    def reset!
      Warg.console.output.clear
      Warg.instance_variable_set(:@config, Config.new)

      Command.registry.each do |name, command|
        Command.registry.delete(name)

        # Already removed
        unless Object.const_defined?(command.name)
          next
        end

        *parent_parts, command_module_name = command.name.split("::")

        if parent_parts.empty?
          parent_module = Object
        else
          parent_module_name = parent_parts.join("::")
          parent_module = Object.const_get(parent_module_name)
        end

        parent_module.send(:remove_const, command_module_name)
      end

      $LOADED_FEATURES.grep(/dummy/).each { |path| $LOADED_FEATURES.delete(path) }
    end

    class TestScript
      attr_reader :content

      def initialize(content:, name:)
        @content = content
        @name = name
      end

      def remote_path
        install_directory.join(@name)
      end

      def install_path
        remote_path.relative_path_from Pathname.new("$HOME")
      end

      def install_directory
        Warg::Script::REMOTE_DIRECTORY
      end
    end

    module CaptureStdout
      def self.extended(klass)
        klass.class_eval <<-RUN
          alias_method :default_setup, :setup

          def setup
            default_setup.and_then do |host, outcome, resolver|
              $stdout.puts outcome.stdout
              $stderr.puts outcome.stderr
            end
          end
        RUN
      end
    end

    module ConsoleRedirection
      def self.extended(klass)
        klass.class_eval <<-INIT
          alias_method :original_initialize, :initialize

          def initialize
            original_initialize

            @io = StringIO.new
          end

          def redirecting_stdout_and_stderr
            yield
          end

          def output
            io.string
          end
        INIT

        klass.send :attr_reader, :cursor_position
        klass.send :attr_reader, :history
        klass.send :attr_reader, :io
      end
    end

    Console.extend ConsoleRedirection
  end

  class Runner
    attr_reader :context
  end

  module Command::BehaviorWithoutRegistration
    def on_failure(execution_result)
      failure_reason = execution_result.map do |outcome|
        outcome.failure_reason
      end.join("\n")

      fail "`#{name}' failed because #{failure_reason}"
    end
  end
end

module Net
  module SSH
    class Config
      def self.default_files
        @@default_files.clone.unshift Warg::Testing::VAGRANT_SSH_CONFIG
      end
    end

    module Authentication
      class Session
        private

        alias_method :original_default_keys, :default_keys

        def default_keys
          original_default_keys.unshift(Warg::Testing::VAGRANT_PRIVATE_KEY)
        end
      end
    end
  end
end

class Minitest::Test
  def setup
    Warg::Testing.chdir_to_dummy_directory
  end

  def teardown
    Warg::Testing.reset!
  end
end
