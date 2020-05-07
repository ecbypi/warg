require "test_helper"

class WargContextTest < Minitest::Test
  def test_copying_config_values
    config = Warg::Config.new
    context = Warg::Context.new([])

    config.hosts = "nobody@localhost?environment=nubanuba"

    config.variables(:email_notification) do |email|
      email.recipients = %w( buddy@guy.com support@guy.com )
      email.from = "deploys@guy.com"
    end

    config.variables(:app) do |app|
      app.name = "warg-testing-app"
    end

    config.variables(:deploy) do |deploy|
      deploy.timestamp = proc { Time.new(2020, 4, 20, 4, 20) }
      deploy.tag { timestamp.strftime("%Y-%m-%d--%H-%M-%S") }
      deploy.path { "/srv/#{context.app.name}" }
    end

    context.copy(config)

    assert_equal ["ssh://nobody@localhost?environment=nubanuba"], context.hosts.map(&:to_s)

    assert_equal "warg-testing-app", config.app.name
    assert_equal Time.new(2020, 4, 20, 4, 20), config.deploy.timestamp
    assert_equal "2020-04-20--04-20-00", config.deploy.tag
    assert_equal "/srv/warg-testing-app", config.deploy.path

    assert_equal %w( buddy@guy.com support@guy.com ), config.email_notification.recipients
    assert_equal "deploys@guy.com", config.email_notification.from
  end
end
