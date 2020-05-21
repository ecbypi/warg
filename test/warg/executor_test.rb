require "test_helper"
require "concurrent/array"

class WargExecutorTest < Minitest::Test
  def test_parallel_execution
    hosts = Warg::HostCollection.from [
      "vagrant@warg-testing",
      "vagrant@localhost:2222"
    ]

    executor = Warg::Executor.for(:parallel).new(hosts)
    results = Concurrent::Array.new

    executor.run do |host|
      if host.address == "localhost"
        sleep 0.1
      elsif host.address == "warg-testing"
        sleep 0.3
      end

      results << host.address
    end

    # `localhost` appears second because we wait for it to complete longer than `warg-testing`.
    assert_equal ["localhost", "warg-testing"], results
  end

  def test_serial_execution
    hosts = Warg::HostCollection.from [
      "vagrant@warg-testing",
      "vagrant@localhost:2222",
      "nuba-nuba"
    ]

    executor = Warg::Executor.for(:serial).new(hosts)
    results = Concurrent::Array.new

    executor.run do |host|
      if host.address == "localhost"
        sleep 0.1
      elsif host.address == "warg-testing"
        sleep 0.3
      end

      results << host.address.reverse
    end

    # order is the the same as in the host collection despite the different wait times
    assert_equal ["gnitset-graw", "tsohlacol", "abun-abun"], results
  end

  def test_registering_custom_strategies
    Warg::Executor.register :every_other_parallel do |&procedure|
      host_promises = hosts.each_with_index.map do |host, index|
        if index.even?
          Concurrent::Promise.execute do
            procedure.call(host)
          end
        end
      end

      Concurrent::Promise.zip(*host_promises.compact)
    end

    hosts = Warg::HostCollection.from [
      "vagrant@warg-testing",
      "vagrant@localhost:2222",
      "nuba-nuba"
    ]

    executor = Warg::Executor.for(:every_other_parallel).new(hosts)
    results = Concurrent::Array.new

    executor.run do |host|
      if host.address == "localhost"
        sleep 0.1
      elsif host.address == "warg-testing"
        sleep 0.3
      end

      results << host.address
    end

    # `localhost` is skipped and `warg-testing` appears second because we waited
    assert_equal ["nuba-nuba", "warg-testing"], results
  end
end