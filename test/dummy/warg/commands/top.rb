class Top
  include Warg::Command::Behavior

  def run
  end

  def configure_parser!
    parser.on("-u USER", "user to filter processes for") do |user|
      context.variables(:top) do |top|
        top.user = user
      end
    end
  end
end
