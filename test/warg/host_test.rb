require "test_helper"

class WargHostTest < Minitest::Test
  def test_from_with_hahes
    host = Warg::Host.from(user: "rob", address: "localhost", properties: { stage: "demo" })

    assert_equal "ssh://rob@localhost?stage=demo", host.to_s
  end

  def test_from_with_array_with_a_hash
    host_data = [{ address: "192.168.0.43", properties: { app: "tidy" } }]

    host = Warg::Host.from(host_data)

    assert_equal "ssh://192.168.0.43?app=tidy", host.to_s
  end

  def test_from_with_string_and_properties
    host_data = ["lauren@app.product.com:20202?stage=production", "team=product", app: "spunky"]

    host = Warg::Host.from(host_data)

    assert_equal "ssh://lauren@app.product.com:20202?stage=production&app=spunky&team=product", host.to_s
  end

  def test_from_with_connection_string
    host = Warg::Host.from("patsy@signin.beta.app.com?stage=beta")

    assert_equal "ssh://patsy@signin.beta.app.com?stage=beta", host.to_s
  end

  def test_hash_like_access_to_properties
    host = Warg::Host.new(address: "localhost", properties: { environment: "non-hippa" })

    assert_equal host["environment"], "non-hippa"
  end

  def test_hash_like_setting_properties
    host = Warg::Host.new(address: "localhost")

    assert_equal "ssh://localhost", host.to_s

    host[:environment] = "hippa"

    assert_equal "ssh://localhost?environment=hippa", host.to_s
  end

  def test_uploading_files
    host = Warg::Host.new(address: "warg-testing")

    tempfile = Tempfile.new
    tempfile.write("here-i-am")
    tempfile.rewind

    host.upload(tempfile, to: "see-me")

    cat_output = host.run_command("cat see-me")

    assert_equal 0, cat_output.exit_status
    assert_equal "here-i-am", cat_output.stdout

    rm_output = host.run_command("rm see-me")

    assert_equal 0, rm_output.exit_status
    assert_equal "", rm_output.stderr
  ensure
    tempfile.unlink
  end

  def test_creating_files_from_string_content
    host = Warg::Host.new(address: "warg-testing")

    host.create_file_from <<~SCRIPT, path: "see-me.sh", mode: 0755
      #!/usr/bin/env bash

      printf "here-i-am"
    SCRIPT

    script_output = host.run_command("./see-me.sh")

    assert_equal 0, script_output.exit_status
    assert_equal "here-i-am", script_output.stdout

    rm_output = host.run_command("rm see-me.sh")

    assert_equal 0, rm_output.exit_status
    assert_equal "", rm_output.stderr
  end
end
