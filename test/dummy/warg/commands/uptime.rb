class Uptime < Warg::Command
  def run
    @context.hosts.each do |host|
      output = host.run_command("uptime")
      $stdout.puts output.stdout
    end
  end
end
