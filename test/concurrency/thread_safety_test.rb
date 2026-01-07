# frozen_string_literal: true

require "test_helper"

module MessagingSystem
  class ThreadSafetyTest < Minitest::Test
    include TestHelpers

    def setup
      @logger = MockLogger.new
      @broker = MessageBroker.new(test_mode: false, logger: @logger)
    end

    def teardown
      @broker.shutdown(timeout: 10)
    end

    def test_concurrent_publishing
      errors = Queue.new
      received = Queue.new

      subscriber = Subscriber.new("test", broker: @broker, async: true, worker_count: 5)
      subscriber.subscribe("test") { |msg| received << msg }

      sleep 0.1

      threads = 10.times.map do |t|
        Thread.new do
          10.times do |i|
            Publisher.new(broker: @broker).publish("test", { thread: t, msg: i })
          rescue StandardError => e
            errors << e
          end
        end
      end

      threads.each(&:join)

      deadline = Time.now + 5
      sleep 0.1 until received.size >= 100 || Time.now > deadline

      assert_empty errors, "Expected no errors, got: #{errors.size}"
      assert_equal 100, received.size
    end

    def test_concurrent_subscription
      threads = 10.times.map do |i|
        Thread.new do
          subscriber = Subscriber.new("sub-#{i}", broker: @broker, async: true)
          subscriber.subscribe("test") { |_msg| }
        end
      end

      threads.each(&:join)

      assert_equal 10, @broker.subscriber_count
    end

    def test_concurrent_publish_and_subscribe
      received = Queue.new
      errors = Queue.new

      publish_threads = 5.times.map do |t|
        Thread.new do
          20.times do |i|
            Publisher.new(broker: @broker).publish("test.#{t}", { msg: i })
          rescue StandardError => e
            errors << e
          end
        end
      end

      subscribe_threads = 5.times.map do |t|
        Thread.new do
          subscriber = Subscriber.new("sub-#{t}", broker: @broker, async: true)
          subscriber.subscribe("test.*") { |msg| received << msg }
        end
      end

      subscribe_threads.each(&:join)
      publish_threads.each(&:join)

      sleep 0.5

      assert_empty errors, "Expected no errors"
    end

    def test_message_immutability_under_concurrency
      message = create_test_message(payload: { count: 0 })
      errors = Queue.new

      threads = 10.times.map do
        Thread.new do
          100.times do
            message.payload[:count] = 1
          rescue FrozenError
            # Expected - message is frozen, which is what we're testing
            nil
          rescue StandardError => e
            errors << e
          end
        end
      end

      threads.each(&:join)

      assert_empty errors
      assert_equal 0, message.payload[:count]
    end

    def test_broker_stats_thread_safe
      threads = 10.times.map do
        Thread.new do
          100.times { @broker.stats }
        end
      end

      assert_nothing_raised { threads.each(&:join) }
    end

    def test_queue_operations_thread_safe
      queue = MessageQueue.new(capacity: 1000)
      errors = Queue.new

      producers = 5.times.map do
        Thread.new do
          100.times do
            queue.push(create_test_message)
          rescue StandardError => e
            errors << e
          end
        end
      end

      consumers = 5.times.map do
        Thread.new do
          100.times do
            queue.pop(timeout: 0.1)
          rescue StandardError => e
            errors << e
          end
        end
      end

      producers.each(&:join)
      consumers.each(&:join)
      queue.close

      assert_empty errors, "Expected no errors, got: #{errors.size}"
    end

    private

    def assert_nothing_raised
      yield
    end
  end
end
