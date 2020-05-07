class Uptime < Warg::Command
  def run
    run_command "uptime", order: :parallel do |output|
      $stdout.puts output.stdout
    end
  end
end
