class Uptime < Warg::Command
  def run
    run_command "uptime", order: :parallel do |host, outcome|
      $stdout.puts outcome.stdout
    end
  end
end
