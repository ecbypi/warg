require "test_helper"

class WargScriptTemplateTest < Minitest::Test
  def test_fails_by_default_on_lookup
    assert_raises(RuntimeError) { Warg::Script::Template.find("no-se-encuentra") }
  end

  def test_returns_empty_template_otherwise
    assert_equal Warg::Script::Template::MISSING, Warg::Script::Template.find("donde-esta", fail_if_missing: false)
  end

  def test_missing_template_compile_compatible
    assert_equal "", Warg::Script::Template::MISSING.compile(hay: "nada")
  end
end
