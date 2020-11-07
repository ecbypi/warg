require "test_helper"

class WargVariableSetTest < Minitest::Test
  def test_accessing_properties_before_defined
    config = Warg::Config.new
    variable_set = Warg::Config::VariableSet.new("ejemplo", config)

    assert_output nil, "`ejemplo.perdido' was accessed before it was defined\n" do
      variable_set.perdido
    end

    assert_silent do
      variable_set.perdido { true }
    end

    assert_equal true, variable_set.perdido
    assert_respond_to variable_set, :perdido
  end

  def test_switching_between_lazy_and_static_properties
    config = Warg::Config.new
    variable_set = Warg::Config::VariableSet.new("cocina", config)

    variable_set.pintada { false }

    assert_equal false, variable_set.pintada

    variable_set.pintada = true

    assert_equal true, variable_set.pintada
  end

  def test_raising_no_method_error_on_unsupported_property_names
    config = Warg::Config.new
    variable_set = Warg::Config::VariableSet.new("cancha", config)

    assert_raises NoMethodError do
      variable_set.wepa! { true }
    end
  end

  def test_checking_for_defined_properties
    config = Warg::Config.new
    variable_set = Warg::Config::VariableSet.new("alrededor", config)

    refute variable_set.defined?(:la_esquina)
    refute variable_set.defined?("la_esquina")

    variable_set.la_esquina = true

    assert variable_set.defined?(:la_esquina)
    assert variable_set.defined?("la_esquina")
  end

  def test_context_is_a_protected_method
    config = Warg::Config.new
    variable_set = Warg::Config::VariableSet.new("supermercado", config)

    assert_equal config, variable_set.context

    assert_raises NotImplementedError do
      variable_set.context = nil
    end
  end
end
