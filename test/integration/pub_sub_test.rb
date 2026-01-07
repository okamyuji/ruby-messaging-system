# frozen_string_literal: true

require "test_helper"

module MessagingSystem
  class PubSubIntegrationTest < Minitest::Test
    include TestHelpers

    def setup
      @logger = MockLogger.new
      @broker = MessageBroker.new(test_mode: false, logger: @logger)
    end

    def teardown
      @broker.shutdown(timeout: 5)
    end

    def test_simple_pub_sub_flow
      received = Queue.new

      subscriber = Subscriber.new("test", broker: @broker, async: true, worker_count: 2)
      subscriber.subscribe("orders.*") { |msg| received << msg }

      sleep 0.1

      publisher = Publisher.new(broker: @broker)
      publisher.publish("orders.created", { order_id: 123 })

      message = nil
      Timeout.timeout(2) { message = received.pop }

      assert_equal "orders.created", message.topic
      assert_equal({ order_id: 123 }, message.payload)
    end

    def test_fan_out_to_multiple_subscribers
      received1 = Queue.new
      received2 = Queue.new

      sub1 = Subscriber.new("sub1", broker: @broker, async: true)
      sub1.subscribe("orders.created") { |msg| received1 << msg }

      sub2 = Subscriber.new("sub2", broker: @broker, async: true)
      sub2.subscribe("orders.created") { |msg| received2 << msg }

      sleep 0.1

      publisher = Publisher.new(broker: @broker)
      publisher.publish("orders.created", { id: 1 })

      msg1 = nil
      msg2 = nil
      Timeout.timeout(2) do
        msg1 = received1.pop
        msg2 = received2.pop
      end

      assert_equal "orders.created", msg1.topic
      assert_equal "orders.created", msg2.topic
    end

    def test_wildcard_routing
      received = Queue.new

      subscriber = Subscriber.new("test", broker: @broker, async: true)
      subscriber.subscribe("orders.#") { |msg| received << msg }

      sleep 0.1

      publisher = Publisher.new(broker: @broker)
      publisher.publish("orders.created", {})
      publisher.publish("orders.updated", {})
      publisher.publish("orders.items.added", {})

      messages = []
      3.times do
        Timeout.timeout(2) { messages << received.pop }
      end

      topics = messages.map(&:topic).sort
      assert_equal ["orders.created", "orders.items.added", "orders.updated"], topics
    end

    def test_message_ordering_preserved
      received = Queue.new

      subscriber = Subscriber.new("test", broker: @broker, async: true, worker_count: 1)
      subscriber.subscribe("test") { |msg| received << msg }

      sleep 0.1

      publisher = Publisher.new(broker: @broker)
      10.times { |i| publisher.publish("test", { order: i }) }

      messages = []
      10.times do
        Timeout.timeout(2) { messages << received.pop }
      end

      orders = messages.map { |m| m.payload[:order] }
      assert_equal (0..9).to_a, orders
    end

    def test_late_subscriber_does_not_receive_old_messages
      publisher = Publisher.new(broker: @broker)
      publisher.publish("test", { msg: "before" })

      received = Queue.new
      subscriber = Subscriber.new("test", broker: @broker, async: true)
      subscriber.subscribe("test") { |msg| received << msg }

      sleep 0.1

      publisher.publish("test", { msg: "after" })

      message = nil
      Timeout.timeout(2) { message = received.pop }

      assert_equal "after", message.payload[:msg]
      assert_empty received
    end

    def test_graceful_shutdown_processes_pending
      received = Queue.new

      subscriber = Subscriber.new("test", broker: @broker, async: true, worker_count: 2)
      subscriber.subscribe("test") do |msg|
        sleep 0.05
        received << msg
      end

      sleep 0.1

      publisher = Publisher.new(broker: @broker)
      10.times { |i| publisher.publish("test", { order: i }) }

      @broker.shutdown(timeout: 10)

      assert_equal 10, received.size
    end
  end
end
