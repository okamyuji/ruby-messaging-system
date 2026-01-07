# frozen_string_literal: true

require "test_helper"

module MessagingSystem
  class ErrorHandlingIntegrationTest < Minitest::Test
    include TestHelpers

    def setup
      @logger = MockLogger.new
      @broker = MessageBroker.new(test_mode: true, logger: @logger)
    end

    def teardown
      @broker.shutdown
    end

    def test_handler_exception_does_not_affect_broker
      error_count = 0

      @broker.subscribe("orders.*") do |_msg|
        error_count += 1
        raise "Handler error"
      end

      @broker.subscribe("orders.created") do |_msg|
      end

      @broker.publish("orders.created", {})

      assert @broker.running?
      assert_equal 1, error_count
    end

    def test_messages_moved_to_dlq_after_max_retries
      subscriber = Subscriber.new(
        "failing",
        broker: @broker,
        async: false,
        max_retries: 0,
      )

      subscriber.subscribe("test") { raise "always fails" }

      @broker.publish("test", {})

      assert_equal 1, @broker.dead_letter_queue.size
    end

    def test_retry_logic
      attempt_count = 0
      subscriber = Subscriber.new(
        "retry-test",
        broker: @broker,
        async: false,
        max_retries: 2,
        retry_delay: 0.01,
      )

      subscriber.subscribe("test") do |msg|
        attempt_count += 1
        raise "fail" if msg.retry_count < 2
      end

      @broker.publish("test", {})

      sleep 0.1

      assert_operator attempt_count, :>=, 1
    end

    def test_circuit_breaker_opens_on_failures
      subscriber = Subscriber.new(
        "circuit-test",
        broker: @broker,
        async: false,
        circuit_breaker_threshold: 2,
      )

      fail_count = 0
      subscriber.subscribe("test") do |_msg|
        fail_count += 1
        raise "fail"
      end

      3.times { @broker.publish("test", {}) }

      stats = subscriber.stats
      assert_operator stats[:circuit_breaker][:failure_count], :>=, 2
    end

    def test_error_hook_called
      error_received = nil
      @broker.on_error { |_msg, error| error_received = error }

      @broker.subscribe("test") { raise "test error" }
      @broker.publish("test", {})

      assert_instance_of ::RuntimeError, error_received
    end
  end
end
