class LocalUser
  include Warg::Command::Behavior

  def setup
    on_localhost "whoami" do
      context.variables(:locally) do |locally|
        locally.user = `whoami`.chomp
      end
    end
  end
end
