# frozen_string_literal: true

require "test_helper"

module MessagingSystem
  class SubscriberTest < Minitest::Test
    include TestHelpers

    def setup
      @logger = MockLogger.new
      @broker = MessageBroker.new(test_mode: true, logger: @logger)
      @subscriber = Subscriber.new(
        "test-subscriber",
        broker: @broker,
        logger: @logger,
        async: false,
      )
    end

    def teardown
      @subscriber.shutdown
      @broker.shutdown
    end

    def test_creates_with_name
      assert_equal "test-subscriber", @subscriber.name
    end

    def test_subscribe_with_block
      subscription = @subscriber.subscribe("orders.*") { |_msg| }

      assert_instance_of Subscription, subscription
      assert_equal 1, @subscriber.subscriptions.size
    end

    def test_subscribe_without_block_raises
      assert_raises(ArgumentError) do
        @subscriber.subscribe("orders.*")
      end
    end

    def test_unsubscribe_by_pattern
      @subscriber.subscribe("orders.*") { |_msg| }
      @subscriber.subscribe("users.*") { |_msg| }

      @subscriber.unsubscribe("orders.*")

      assert_equal 1, @subscriber.subscriptions.size
    end

    def test_unsubscribe_by_subscription
      subscription = @subscriber.subscribe("orders.*") { |_msg| }

      @subscriber.unsubscribe(subscription)

      assert_equal 0, @subscriber.subscriptions.size
    end

    def test_receive_message_sync
      received = nil
      @subscriber.subscribe("test.topic") { |msg| received = msg }

      message = create_test_message
      @subscriber.receive(message)

      assert_equal message, received
    end

    def test_pause_and_resume
      received = []
      @subscriber.subscribe("test.topic") { |msg| received << msg }

      @subscriber.pause
      @subscriber.receive(create_test_message)

      assert_equal 0, received.size

      @subscriber.resume
      @subscriber.receive(create_test_message)

      assert_equal 1, received.size
    end

    def test_expired_messages_skipped
      received = []
      @subscriber.subscribe("test.topic") { |msg| received << msg }

      expired_message = Message.new(
        topic: "test.topic",
        payload: {},
        expires_at: Time.now - 1,
      )
      @subscriber.receive(expired_message)

      assert_equal 0, received.size
    end

    def test_stats
      @subscriber.subscribe("orders.*") { |_msg| }

      stats = @subscriber.stats

      assert_equal "test-subscriber", stats[:name]
      assert_equal 1, stats[:subscription_count]
      refute stats[:paused]
    end

    def test_async_mode
      async_subscriber = Subscriber.new(
        "async-test",
        broker: @broker,
        logger: @logger,
        async: true,
        worker_count: 2,
      )

      received = Queue.new
      async_subscriber.subscribe("test.topic") { |msg| received << msg }

      sleep 0.1

      message = create_test_message
      async_subscriber.receive(message)

      result = nil
      Timeout.timeout(2) { result = received.pop }

      assert_equal message.id, result.id
    ensure
      async_subscriber&.shutdown
    end

    def test_error_handling
      @subscriber.subscribe("test.topic") { raise "handler error" }

      message = create_test_message
      @subscriber.receive(message)

      error_logs = @logger.messages_at(:error)
      assert error_logs.any? { |l| l[:message].include?("error") }
    end

    def test_running_status
      async_subscriber = Subscriber.new(
        "running-test",
        broker: @broker,
        async: true,
      )

      async_subscriber.subscribe("test") { |_msg| }
      assert async_subscriber.running?

      async_subscriber.shutdown
      refute async_subscriber.running?
    end
  end
end
