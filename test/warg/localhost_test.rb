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
end
