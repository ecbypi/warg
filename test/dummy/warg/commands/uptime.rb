class Uptime < Warg::Command
  def run
    deferred = run_command "uptime", order: :parallel

    deferred.and_then do |host, outcome, resolver|
      if outcome.stdout.empty?
        resolver.fail!
      end

      $stdout.puts outcome.stdout
    end
  end
end
