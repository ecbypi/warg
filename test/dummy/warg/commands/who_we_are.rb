class WhoWeAre < Warg::Command
  def run
    locally "local step" do
      context.variables(:log_test) do |log_test|
        log_test.local_user = `whoami`.chomp
      end
    end

    whoami = run_command "whoami", on: Warg::HostCollection.from(["warg@warg-testing"])
    whoami.and_then do |host, result|
      context.variables(:log_test) do |log_test|
        log_test.remote_user = result.stdout.chomp
      end
    end
  end
end
