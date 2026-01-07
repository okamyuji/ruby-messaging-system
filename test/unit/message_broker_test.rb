# frozen_string_literal: true

require "test_helper"

module MessagingSystem
  class MessageBrokerTest < Minitest::Test
    include TestHelpers

    def setup
      @logger = MockLogger.new
      @broker = MessageBroker.new(test_mode: true, logger: @logger)
    end

    def teardown
      @broker.shutdown
    end

    def test_publish_creates_message
      message = @broker.publish("orders.created", { order_id: 123 })

      assert_instance_of Message, message
      assert_equal "orders.created", message.topic
    end

    def test_subscribe_creates_subscriber
      subscriber = @broker.subscribe("orders.*") { |_msg| }

      assert_instance_of Subscriber, subscriber
      assert_equal 1, @broker.subscriber_count
    end

    def test_routes_message_to_subscriber
      received = nil
      @broker.subscribe("orders.*") { |msg| received = msg }

      @broker.publish("orders.created", { order_id: 123 })

      assert_equal({ order_id: 123 }, received.payload)
    end

    def test_routes_to_multiple_subscribers
      received1 = nil
      received2 = nil

      @broker.subscribe("orders.*") { |msg| received1 = msg }
      @broker.subscribe("orders.created") { |msg| received2 = msg }

      @broker.publish("orders.created", { order_id: 123 })

      refute_nil received1
      refute_nil received2
    end

    def test_no_routing_to_unmatched_subscribers
      received = nil
      @broker.subscribe("users.*") { |msg| received = msg }

      @broker.publish("orders.created", { order_id: 123 })

      assert_nil received
    end

    def test_published_messages_in_test_mode
      @broker.publish("test1", {})
      @broker.publish("test2", {})

      messages = @broker.published_messages

      assert_equal 2, messages.size
      assert_equal "test1", messages[0].topic
      assert_equal "test2", messages[1].topic
    end

    def test_published_messages_not_available_in_production_mode
      broker = MessageBroker.new(test_mode: false)

      assert_raises(::RuntimeError) { broker.published_messages }
    ensure
      broker.shutdown
    end

    def test_reset
      @broker.subscribe("test") { |_msg| }
      @broker.publish("test", {})

      @broker.reset!

      assert_equal 0, @broker.subscriber_count
      assert_equal 0, @broker.published_messages.size
    end

    def test_shutdown
      @broker.subscribe("test") { |_msg| }
      @broker.shutdown

      refute @broker.running?
    end

    def test_publish_after_shutdown_raises
      @broker.shutdown

      assert_raises(ShutdownError) do
        @broker.publish("test", {})
      end
    end

    def test_on_publish_hook
      hook_called = false
      @broker.on_publish { |_msg| hook_called = true }

      @broker.publish("test", {})

      assert hook_called
    end

    def test_on_consume_hook
      hook_called = false
      @broker.on_consume { |_msg| hook_called = true }
      @broker.subscribe("test") { |_msg| }

      @broker.publish("test", {})

      assert hook_called
    end

    def test_on_shutdown_hook
      hook_called = false
      @broker.on_shutdown { hook_called = true }

      @broker.shutdown

      assert hook_called
    end

    def test_stats
      @broker.subscribe("test") { |_msg| }
      @broker.publish("test", {})

      stats = @broker.stats

      assert stats[:running]
      assert stats[:test_mode]
      assert_equal 1, stats[:subscriber_count]
      assert_equal 1, stats[:published_count]
    end

    def test_health
      @broker.subscribe("test") { |_msg| }

      health = @broker.health

      assert_equal "healthy", health[:status]
      assert_equal "ok", health[:broker]
    end

    def test_dead_letter_queue_accessible
      dlq = @broker.dead_letter_queue

      assert_instance_of DeadLetterQueue, dlq
    end

    def test_topic_matcher_accessible
      matcher = @broker.topic_matcher

      assert_instance_of TopicMatcher, matcher
    end

    def test_subscription_count
      @broker.subscribe("orders.*") { |_msg| }
      @broker.subscribe("users.*") { |_msg| }

      assert_equal 2, @broker.subscription_count
    end

    def test_backpressure_detection
      refute @broker.backpressure?
    end
  end
end
