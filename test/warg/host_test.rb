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

  def test_from_with_invalid_array
    error = assert_raises(Warg::InvalidHostDataError) do
      Warg::Host.from([["localhost"]])
    end

    assert_equal %{could not instantiate a host from `[["localhost"]]'}, error.message
  end

  def test_from_with_invalid_data
    error = assert_raises(Warg::InvalidHostDataError) do
      Warg::Host.from(1)
    end

    assert_equal %{could not instantiate a host from `1'}, error.message
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

  def test_equality_matches_other_host_objects_only_with_the_same_uri
    host = Warg::Host.new(address: "localhost")
    other_host = Warg::Host.new(address: "localhost")

    assert_equal host, other_host

    host["stage"] = "production"

    refute_equal host, other_host
    refute_equal host, host.uri
  end

  def test_uploading_and_downloading_files
    host = Warg::Host.new(address: "warg-testing")

    tempfile = Tempfile.new
    tempfile.write("here-i-am")
    tempfile.rewind

    host.upload(tempfile, to: "see-me")

    cat_result = host.run_command("cat see-me")

    assert_equal 0, cat_result.exit_status
    assert_equal "here-i-am", cat_result.stdout

    download = host.download("see-me", to: "see-me-local")

    assert_path_exists File.join(Dir.pwd, "see-me-local")
    assert_equal "here-i-am", download.read

    rm_result = host.run_command("rm see-me")

    assert_equal 0, rm_result.exit_status
    assert_equal "", rm_result.stderr
  ensure
    download.close
    File.delete(download.path)

    tempfile.unlink
  end

  def test_creating_files_from_string_content
    host = Warg::Host.new(address: "warg-testing")

    host.create_file_from <<~SCRIPT, path: "see-me.sh", mode: 0755
      #!/usr/bin/env bash

      printf "here-i-am"
    SCRIPT

    script_result = host.run_command("./see-me.sh")

    assert_equal 0, script_result.exit_status
    assert_equal "here-i-am", script_result.stdout

    rm_result = host.run_command("rm see-me.sh")

    assert_equal 0, rm_result.exit_status
    assert_equal "", rm_result.stderr
  end

  def test_outcome_for_stdout_and_stderr
    host = Warg::Host.new(address: "nuba-nuba", user: "warg")

    stdout_outcome = host.run_command %{printf "this is on stdout"}
    stderr_outcome = host.run_command %{1>&2 printf "this is on stderr"}

    assert_equal "this is on stdout", stdout_outcome.stdout
    assert_equal "", stdout_outcome.stderr

    assert_equal "", stderr_outcome.stdout
    assert_equal "this is on stderr", stderr_outcome.stderr
  end

  def test_outcome_for_command_failure_from_connection_errors
    # multiple hosts to test different reasons `Net::SSH.start` will fail
    hosts = [
      Warg::Host.new(address: "jub-jub", user: "warg"),    # no such host
      Warg::Host.new(address: "localhost", port: 22222),      # host exists, port 222 not open
      Warg::Host.new(address: "warg-testing", user: "chanel") # host exists, incorrect user
    ]

    socket_error_result, connection_refused_error_result, authentication_error_result = hosts.map do |host|
      result = host.run_command "ls"

      # common properties of all errors; place here to avoid repeating
      assert result.failed?
      assert_equal :connection_error, result.failure_reason
      assert_equal(-1, result.connection_error_code)
      assert_nil result.started_at
      assert_nil result.finished_at

      result
    end

    assert_match(/SocketError/, socket_error_result.connection_error_reason)
    assert_match(/Errno::ECONNREFUSED/, connection_refused_error_result.connection_error_reason)
    assert_match(/Net::SSH::AuthenticationFailed/, authentication_error_result.connection_error_reason)
  end

  def test_outcome_for_command_failure_from_nonzero_exit_status
    host = Warg::Host.from "warg@warg-testing"

    result = host.run_command "exit 37"

    assert result.failed?
    refute result.successful?

    assert_equal :nonzero_exit_status, result.failure_reason

    assert_equal 37, result.exit_status
    assert_nil result.exit_signal

    refute_nil result.duration
  end

  def test_outcome_for_command_failure_from_exit_signal
    host = Warg::Host.from "warg@warg-testing"

    script_content = <<~SCRIPT
      #!/usr/bin/env bash

      kill -9 $$
    SCRIPT

    script = Warg::Testing::TestScript.new(content: script_content, name: "test-exit-signal")

    result = host.run_script script

    assert result.failed?
    refute result.successful?

    assert_equal :exit_signal, result.failure_reason

    assert_equal "KILL", result.exit_signal
    assert_nil result.exit_status

    refute_nil result.duration
  end
end
