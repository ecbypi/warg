class Uptime < Warg::Command
  def run
    run_command "uptime", order: :parallel do |host, performance|
      performance.on_stdout do |data, host|
        $stdout.puts data
      end
    end
  end
end
