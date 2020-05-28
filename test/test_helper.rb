require "simplecov"
SimpleCov.start do
  add_filter %r{^/(?:warg|test)/}
  enable_coverage :branch
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
  module Testing
    module_function

    VAGRANT_SSH_CONFIG = File.expand_path("ssh_config", __dir__)
    VAGRANT_PRIVATE_KEY = File.expand_path \
      File.join("..", ".vagrant", "machines", "warg-testing", "virtualbox", "private_key"),
      __dir__


    class << self
      attr_accessor :runner
      attr_accessor :dummy_directory
    end

    self.dummy_directory = Pathname.new File.expand_path(File.join("dummy", "warg"), __dir__)

    def chdir_to_dummy_directory
      Dir.chdir dummy_directory
    end

    def reset!
      Warg.instance_variable_set(:@config, Config.new)

      Command.registry.each do |name, command|
        Command.registry.delete(name)
        Object.send(:remove_const, command.name)
      end
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
        remote_path.relative_path_from("$HOME")
      end

      def install_directory
        Warg::Script::REMOTE_DIRECTORY
      end
    end

    module CaptureStdout
      def self.extended(klass)
        klass.alias_method :default_run, :run
        klass.class_eval <<-RUN
          def run
            outputs = default_run

            outputs.each do |output|
              $stdout.puts output.stdout
              $stderr.puts output.stderr
            end
          end
        RUN
      end
    end
  end
end

module Net
  module SSH
    class Config
      def self.default_files
        @@default_files.clone.unshift Warg::Testing::VAGRANT_SSH_CONFIG
      end

      class << self
        alias_method :default_for, :for

        def for(host, files=expandable_default_files)
          result = default_for(host, files)

          result[:keys] = Array(result[:keys]).unshift(Warg::Testing::VAGRANT_PRIVATE_KEY)
          result
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
