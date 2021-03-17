class Broken < Warg::Command
  def run
    context.variables(:locally) do |locally|
      locally.failed = false
    end

    on_localhost "whoami" do
      raise "nothing here"
    end
  end

  def on_failure(execution_result)
    outcome = execution_result.value[0]

    context.variables(:locally) do |locally|
      locally.failure = outcome.error
    end
  end
end
