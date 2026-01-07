# frozen_string_literal: true

require "test_helper"

module MessagingSystem
  class CircuitBreakerTest < Minitest::Test
    def setup
      @logger = MockLogger.new
      @breaker = CircuitBreaker.new(
        name: "test",
        failure_threshold: 3,
        success_threshold: 2,
        timeout: 1,
        logger: @logger,
      )
    end

    def test_starts_closed
      assert @breaker.closed?
      refute @breaker.open?
      refute @breaker.half_open?
    end

    def test_executes_block_when_closed
      result = @breaker.call { "success" }

      assert_equal "success", result
    end

    def test_opens_after_failure_threshold
      3.times do
        assert_raises(StandardError) do
          @breaker.call { raise StandardError, "error" }
        end
      end

      assert @breaker.open?
    end

    def test_raises_when_open
      @breaker.force_open

      assert_raises(CircuitBreakerOpenError) do
        @breaker.call { "should not run" }
      end
    end

    def test_transitions_to_half_open_after_timeout
      @breaker.force_open

      sleep 1.1

      assert_raises(StandardError) do
        @breaker.call { raise StandardError, "error" }
      end

      assert @breaker.open?
    end

    def test_closes_after_success_threshold_in_half_open
      breaker = CircuitBreaker.new(
        name: "test",
        failure_threshold: 1,
        success_threshold: 2,
        timeout: 0.1,
        logger: @logger,
      )

      assert_raises(StandardError) { breaker.call { raise StandardError, "error" } }
      assert breaker.open?

      sleep 0.15

      breaker.call { "success" }
      assert breaker.half_open?

      breaker.call { "success" }
      assert breaker.closed?
    end

    def test_returns_to_open_on_failure_in_half_open
      breaker = CircuitBreaker.new(
        name: "test",
        failure_threshold: 1,
        success_threshold: 2,
        timeout: 0.1,
        logger: @logger,
      )

      assert_raises(StandardError) { breaker.call { raise StandardError, "error" } }
      sleep 0.15

      breaker.call { "success" }
      assert breaker.half_open?

      assert_raises(StandardError) { breaker.call { raise StandardError, "error" } }
      assert breaker.open?
    end

    def test_reset
      @breaker.force_open
      @breaker.reset

      assert @breaker.closed?
      assert_equal 0, @breaker.failure_count
      assert_equal 0, @breaker.success_count
    end

    def test_force_open
      @breaker.force_open

      assert @breaker.open?
    end

    def test_stats
      stats = @breaker.stats

      assert_equal "test", stats[:name]
      assert_equal :closed, stats[:state]
      assert_equal 0, stats[:failure_count]
      assert_equal 3, stats[:failure_threshold]
    end

    def test_state_change_callback
      state_changes = []
      breaker = CircuitBreaker.new(
        name: "test",
        failure_threshold: 1,
        timeout: 0.1,
        logger: @logger,
        on_state_change: ->(old_state, new_state) { state_changes << [old_state, new_state] },
      )

      assert_raises(StandardError) { breaker.call { raise StandardError, "error" } }

      assert_equal [[:closed, :open]], state_changes
    end
  end
end
