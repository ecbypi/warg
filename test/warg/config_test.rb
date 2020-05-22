require "test_helper"

class WargConfigTest < Minitest::Test
  def test_defining_variable_sets
    config = Warg::Config.new

    config.variables(:deploy) do |deploy|
      deploy.user { context.app.name }
      deploy.path { "#{root}/#{context.app.name}" }
      deploy.root = "/srv"
      deploy.timestamp { Time.new(2020, 4, 20, 4, 20) }
    end

    config.variables(:app) do |app|
      app.name { "yummy-only" }
    end

    assert_equal "yummy-only", config.app.name
    assert_equal "yummy-only", config.deploy.user
    assert_equal "/srv/yummy-only", config.deploy.path
    assert_equal Time.new(2020, 4, 20, 4, 20), config.deploy.timestamp
  end

  def test_hash_like_access_for_variable_sets
    config = Warg::Config.new

    config.variables(:demo) do |demo|
      demo.probability = 0.3
    end

    assert_equal 0.3, config[:demo].probability
    assert_equal 0.3, config["demo"].probability
    assert_nil config["nada"]
  end
end
