module Chaining
  extend Warg::Command::Behavior

  def self.call(context)
    First.(context) | Second
    Combined.(context)
    Third.(context)
  end

  class First < Warg::Command
    def run
      context.chain_example.deposits << "first"
    end
  end

  class Second < Warg::Command
    def run
      context.chain_example.deposits << "second"
    end
  end

  class Third < Warg::Command
    def run
      chain First, Second
      context.chain_example.deposits << "third"
    end
  end

  Combined = First | Second | First
end
