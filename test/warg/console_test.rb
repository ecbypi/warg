require "test_helper"

class WargConsoleTest < Minitest::Test
  def test_tracks_cursor_position_as_content_is_added_ignoring_sgr_sequences
    console = Warg::Console.new

    assert_equal 1, console.cursor_position.row
    assert_equal 1, console.cursor_position.column

    console.print Warg::Console::SGR("que tal\nnada").with(text_color: :blue)

    assert_equal 2, console.cursor_position.row
    assert_equal 5, console.cursor_position.column

    console.puts
    console.print Warg::Console::SGR("que linda to hija\n").with(text_color: :cyan, effect: :underline)

    assert_equal 4, console.cursor_position.row
    assert_equal 1, console.cursor_position.column

    host = Warg::Host.from("meseek@dev-null.io")
    # `HostStatus` prints itself when initialized
    Warg::Console::HostStatus.new(host, console)

    assert_equal 5, console.cursor_position.row
    assert_equal 1, console.cursor_position.column
  end

  def test_puts_adds_a_newline_when_missing
    console = Warg::Console.new
    console.puts "que tal"

    assert_equal "que tal\n", console.io.string

    console.puts "que hizo?\n"

    assert_equal "que tal\nque hizo?\n", console.io.string

    console.puts "no me digas!\n\n"

    assert_equal "que tal\nque hizo?\nno me digas!\n\n", console.io.string
  end

  def test_select_graphics_renditions_can_be_combined
    cyan_text_color = Warg::Console::SelectGraphicRendition.new(text_color: :cyan)
    strikethrough_effect = Warg::Console::SelectGraphicRendition.new(effect: :strikethrough)

    combination = (cyan_text_color | strikethrough_effect).modify(background_color: :white)

    assert_equal "\e[47;9;36m", combination.to_s
    assert_equal combination.to_h, {
      text_color: "36",
      background_color: "47",
      effect: "9"
    }

    other_combination = combination.modify(text_color: :magenta)

    assert_equal "\e[47;9;35m", other_combination.to_s
    assert_equal other_combination.to_h, {
      text_color: "35",
      background_color: "47",
      effect: "9"
    }
  end
end
