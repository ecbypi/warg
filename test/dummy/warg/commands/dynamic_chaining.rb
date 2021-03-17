class DynamicChaining
  include Warg::Command::Behavior

  def setup
    locally "chain commands" do
      chain LocalUser
    end

    chain WhoWeAre
  end
end
