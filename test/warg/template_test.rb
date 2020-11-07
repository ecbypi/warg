require "test_helper"

class WargScriptTemplateTest < Minitest::Test
  def setup
    Warg.search_paths.unshift Warg::Testing.dummy_directory
  end

  def teardown
    Warg.search_paths.clear
  end

  def test_finds_with_or_without_extension
    assert Warg::Script::Template.find("process-snapshot.sh")
    assert Warg::Script::Template.find("process-snapshot")
  end

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
