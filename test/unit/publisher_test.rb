# frozen_string_literal: true

require "test_helper"

module MessagingSystem
  class PublisherTest < Minitest::Test
    include TestHelpers

    def setup
      @logger = MockLogger.new
      @broker = MessageBroker.new(test_mode: true, logger: @logger)
      @publisher = Publisher.new(broker: @broker, name: "test-publisher", logger: @logger)
    end

    def teardown
      @broker.shutdown
    end

    def test_publish_returns_message
      message = @publisher.publish("orders.created", { order_id: 123 })

      assert_instance_of Message, message
      assert_equal "orders.created", message.topic
      assert_equal({ order_id: 123 }, message.payload)
    end

    def test_publish_routes_through_broker
      @publisher.publish("orders.created", { order_id: 123 })

      messages = @broker.published_messages
      assert_equal 1, messages.size
      assert_equal "orders.created", messages.first.topic
    end

    def test_publish_with_priority
      message = @publisher.publish("orders.created", {}, priority: :high)

      assert_equal :high, message.priority
    end

    def test_publish_with_headers
      message = @publisher.publish("orders.created", {}, headers: { custom: "value" })

      assert_equal "value", message.headers[:custom]
    end

    def test_publish_with_ttl
      message = @publisher.publish("orders.created", {}, ttl: 3600)

      assert_instance_of Time, message.expires_at
      assert_operator message.expires_at, :>, Time.now
    end

    def test_default_priority
      publisher = Publisher.new(broker: @broker, default_priority: :high)
      message = publisher.publish("test", {})

      assert_equal :high, message.priority
    end

    def test_publish_batch
      messages_data = [
        { topic: "orders.created", payload: { id: 1 } },
        { topic: "orders.updated", payload: { id: 2 } },
        { topic: "orders.deleted", payload: { id: 3 } },
      ]

      results = @publisher.publish_batch(messages_data)

      assert_equal 3, results[:success].size
      assert_equal 0, results[:failed].size
    end

    def test_publish_batch_with_failures
      messages_data = [
        { topic: "valid.topic", payload: { id: 1 } },
        { topic: "", payload: { id: 2 } },
      ]

      results = @publisher.publish_batch(messages_data)

      assert_equal 1, results[:success].size
      assert_equal 1, results[:failed].size
    end

    def test_before_publish_hook
      hook_called = false
      @publisher.on_before_publish { |_msg| hook_called = true }

      @publisher.publish("test", {})

      assert hook_called
    end

    def test_after_publish_hook
      hook_called = false
      @publisher.on_after_publish { |_msg| hook_called = true }

      @publisher.publish("test", {})

      assert hook_called
    end

    def test_stats
      @publisher.publish("test", {})
      @publisher.publish("test", {})

      stats = @publisher.stats

      assert_equal "test-publisher", stats[:name]
      assert_equal 2, stats[:published_count]
      assert_equal 0, stats[:error_count]
    end

    def test_publisher_name_in_headers
      message = @publisher.publish("test", {})

      assert_equal "test-publisher", message.headers[:publisher]
    end
  end
end
