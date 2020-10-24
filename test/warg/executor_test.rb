require "test_helper"

class WargExecutorTest < Minitest::Test
  def test_parallel_execution
    hosts = Warg::HostCollection.from [
      "warg@warg-testing",
      "warg@localhost:2222"
    ]

    executor = Warg::Executor.for(:parallel).new(hosts)
    results = []
    mutex = Mutex.new

    executor.run do |host|
      if host.address == "localhost"
        sleep 0.1
      elsif host.address == "warg-testing"
        sleep 0.3
      end

      mutex.synchronize do
        results << host.address
      end
    end

    # `localhost` appears second because we wait for it to complete longer than `warg-testing`.
    assert_equal ["localhost", "warg-testing"], results
  end

  def test_serial_execution
    hosts = Warg::HostCollection.from [
      "warg@warg-testing",
      "warg@localhost:2222",
      "nuba-nuba"
    ]

    executor = Warg::Executor.for(:serial).new(hosts)
    results = []

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
      threads = collection.each_with_index.map do |host, index|
        if index.even?
          Thread.new do
            procedure.call(host)
          end
        end
      end

      threads.each do |thread|
        thread.join if thread
      end
    end

    hosts = Warg::HostCollection.from [
      "warg@warg-testing",
      "warg@localhost:2222",
      "nuba-nuba"
    ]

    executor = Warg::Executor.for(:every_other_parallel).new(hosts)
    results = []
    mutex = Mutex.new

    executor.run do |host|
      if host.address == "localhost"
        sleep 0.1
      elsif host.address == "warg-testing"
        sleep 0.3
      end

      mutex.synchronize do
        results << host.address
      end
    end

    # `localhost` is skipped and `warg-testing` appears second because we waited
    assert_equal ["nuba-nuba", "warg-testing"], results
  end

  def test_deferred_callbacks_ending_in_success
    hosts = Warg::HostCollection.from ["warg-testing"]
    command_class = Class.new do
      def on_failure(execution_result)
      end
    end

    deferred = Warg::Executor::Deferred.new(command_class.new, "uptime", hosts, :serial)

    deferred.and_then do |host, result, outcome|
      1 + 1
    end

    deferred.and_then do |host, result, outcome|
      4 ** result
    end

    execution_result = deferred.run
    outcome = execution_result.first

    assert_equal 16, outcome.value
    assert_nil outcome.error
    assert outcome.successful?
    refute outcome.failed?
  end

  def test_deferred_callbacks_ending_with_a_runtime_error
    hosts = Warg::HostCollection.from ["warg-testing"]
    command_class = Class.new do
      def on_failure(execution_result)
      end
    end

    deferred = Warg::Executor::Deferred.new(command_class.new, "uptime", hosts, :serial)

    deferred.and_then do |host, result, outcome|
      1 + 1
    end

    deferred.and_then do |host, result, outcome|
      result / 0
    end

    deferred.and_then do |host, result, outcome|
      raise "raising here to show this block is never reached"
    end

    execution_result = deferred.run
    outcome = execution_result.first

    assert_nil outcome.value
    assert_kind_of ZeroDivisionError, outcome.error
    refute outcome.successful?
    assert outcome.failed?
  end

  def test_deferred_callbacks_ending_with_user_specified_error
    hosts = Warg::HostCollection.from ["warg-testing"]
    command_class = Class.new do
      def on_failure(execution_result)
      end
    end

    deferred = Warg::Executor::Deferred.new(command_class.new, "uptime", hosts, :serial)

    deferred.and_then do |host, result, outcome|
      outcome.fail! "quitting!"
    end

    execution_result = deferred.run
    outcome = execution_result.first

    assert_nil outcome.value
    assert_kind_of Warg::Executor::Deferred::CallbackFailedError, outcome.error
    refute outcome.successful?
    assert outcome.failed?
  end
end
