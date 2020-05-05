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
