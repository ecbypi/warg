class D < Warg::Command
  class E < Warg::Command
    def run
    end
  end

  DEA = self | E | A

  def run
  end
end
