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

module Net
  module SSH
    class Config
      VAGRANT_SSH_CONFIG = File.expand_path("ssh_config", __dir__)
      VAGRANT_PRIVATE_KEY = File.expand_path \
        File.join("..", ".vagrant", "machines", "warg-testing", "virtualbox", "private_key"),
        __dir__

      def self.default_files
        @@default_files.clone.unshift VAGRANT_SSH_CONFIG
      end

      class << self
        alias_method :default_for, :for

        def for(host, files=expandable_default_files)
          result = default_for(host, files)

          result[:keys] = Array(result[:keys]).unshift(VAGRANT_PRIVATE_KEY)
          result
        end
      end
    end
  end
end
