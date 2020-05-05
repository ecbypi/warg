require "test_helper"

class WargContextTest < Minitest::Test
  def test_copying_config_values
    config = Warg::Config.new
    context = Warg::Context.new([])

    config.hosts = "nobody@localhost?environment=nubanuba"
    context.copy(config)

    assert_equal ["ssh://nobody@localhost?environment=nubanuba"], context.hosts.map(&:to_s)
  end
end
