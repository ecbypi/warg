require "test_helper"

class WargScriptTest < Minitest::Test
  def test_compilation_with_defaults_and_variables
    Warg.search_paths.unshift Warg::Testing.dummy_directory

    context = Warg::Config.new
    context.variables(:top) do |top|
      top.user = "timothy"
    end

    command_name = Warg::Command::Name.from_relative_script_path("process-snapshot.sh")
    script = Warg::Script.new(command_name, context)

    assert_equal <<~SCRIPT, script.content
#!/usr/bin/env bash

set -o nounset
set -o errexit
set -o pipefail

top_user="timothy"

top -u $top_user -c -b -n 1 -o %MEM
    SCRIPT
  end
end
