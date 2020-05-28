class Uptime < Warg::Command
  def run
    run_command "uptime", order: :parallel do |execution|
      execution.on_stdout do |data|
        $stdout.puts data
      end
    end
  end
end
