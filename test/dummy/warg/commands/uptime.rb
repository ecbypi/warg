class Uptime < Warg::Command
  def run
    $stdout.puts `uptime`
  end
end
