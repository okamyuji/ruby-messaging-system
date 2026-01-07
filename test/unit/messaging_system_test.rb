# frozen_string_literal: true

require "test_helper"

module MessagingSystem
  class MessagingSystemModuleTest < Minitest::Test
    def teardown
      @broker&.reset!
    end

    def test_create_broker
      @broker = MessagingSystem.create_broker(test_mode: true)

      assert_instance_of MessageBroker, @broker
      assert @broker.test_mode
    end

    def test_create_broker_with_options
      logger = MockLogger.new
      @broker = MessagingSystem.create_broker(
        test_mode: true,
        logger: logger,
        max_queue_size: 5_000,
      )

      assert_instance_of MessageBroker, @broker
      assert_equal logger, @broker.logger
    end

    def test_create_publisher
      @broker = MessagingSystem.create_broker(test_mode: true)
      publisher = MessagingSystem.create_publisher(broker: @broker, name: "test-publisher")

      assert_instance_of Publisher, publisher
      assert_equal "test-publisher", publisher.name
    end

    def test_create_publisher_with_options
      @broker = MessagingSystem.create_broker(test_mode: true)
      publisher = MessagingSystem.create_publisher(
        broker: @broker,
        name: "priority-publisher",
        default_priority: :high,
      )

      assert_instance_of Publisher, publisher
      assert_equal :high, publisher.stats[:default_priority]
    end

    def test_create_subscriber
      @broker = MessagingSystem.create_broker(test_mode: true)
      subscriber = MessagingSystem.create_subscriber("test-subscriber", broker: @broker)

      assert_instance_of Subscriber, subscriber
      assert_equal "test-subscriber", subscriber.name
    end

    def test_create_subscriber_with_options
      @broker = MessagingSystem.create_broker(test_mode: true)
      subscriber = MessagingSystem.create_subscriber(
        "custom-subscriber",
        broker: @broker,
        worker_count: 5,
        max_retries: 10,
      )

      assert_instance_of Subscriber, subscriber
      assert_equal "custom-subscriber", subscriber.name
    end
  end
end
