require "test_helper"

class WargScriptTest < Minitest::Test
  def setup
    Warg.search_paths.unshift Warg::Testing.dummy_directory
  end

  def teardown
    Warg.search_paths.clear
  end

  def test_compilation_with_defaults_and_variables
    context = Warg::Config.new
    context.variables(:top) do |top|
      top.user = "timothy"
    end

    script = Warg::Script.new("process-snapshot.sh", context)

    assert_equal <<~SCRIPT, script.content
#!/usr/bin/env bash

set -o nounset
set -o errexit
set -o pipefail

top_user="timothy"

top -u $top_user -c -b -n 1 -o %MEM
    SCRIPT
  end

  def test_compliation_with_missing_variables
    context = Warg::Config.new

    _, stderr = capture_io do
      script = Warg::Script.new("process-snapshot.sh", context)

      assert_equal <<~SCRIPT, script.content
        #!/usr/bin/env bash

        set -o nounset
        set -o errexit
        set -o pipefail

        %{variables:top}

        top -u $top_user -c -b -n 1 -o %MEM
      SCRIPT
    end

    assert_equal <<~OUTPUT, stderr
      [WARN] `variables:top' is not defined in interpolations or context variables
      [WARN]   leaving interpolation `%{variables:top}' as is
    OUTPUT
  end
end
