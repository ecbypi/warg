class DynamicChaining
  include Warg::Command::Behavior

  def run
    locally "chain commands" do
      chain LocalUser
    end

    chain WhoWeAre
  end
end
