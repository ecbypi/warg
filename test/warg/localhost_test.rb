require "test_helper"

class WargLocalhostTest < Minitest::Test
  def test_outcome_for_successful_blocks
    localhost = Warg::Localhost.new

    outcome = localhost.run do
      1 + 1
    end

    assert outcome.started?
    assert outcome.finished?
    refute_nil outcome.duration

    assert outcome.successful?
    refute outcome.failed?

    assert_nil outcome.error
    assert_nil outcome.failure_summary
  end

  def test_outcome_for_blocks_with_errors
    localhost = Warg::Localhost.new

    outcome = localhost.run do
      1 / 0
    end

    assert outcome.started?
    assert outcome.finished?
    refute_nil outcome.duration

    refute outcome.successful?
    assert outcome.failed?

    assert_kind_of ZeroDivisionError, outcome.error
    refute_nil outcome.failure_summary
  end

  def test_deferred_callbacks_ending_in_success
    command_class = Class.new do
      def on_failure(execution_result)
      end
    end

    deferred = Warg::Localhost.new.defer(command_class.new, "locally...", &proc {})

    deferred.and_then do |host, result, outcome|
      1 + 1
    end

    execution_result = deferred.run
    outcome = execution_result.first

    assert_equal 2, outcome.value
    assert_nil outcome.error
  end
end
