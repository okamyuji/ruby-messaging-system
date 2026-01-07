# frozen_string_literal: true

require "test_helper"

module MessagingSystem
  class DeadLetterQueueTest < Minitest::Test
    include TestHelpers

    def setup
      @logger = MockLogger.new
      @dlq = DeadLetterQueue.new(max_size: 100, logger: @logger)
    end

    def test_add_message
      message = create_test_message
      error = StandardError.new("test error")

      entry = @dlq.add(message, error: error, subscriber_name: "test-subscriber")

      assert_equal message, entry[:message]
      assert_equal "StandardError", entry[:error_class]
      assert_equal "test error", entry[:error_message]
      assert_equal "test-subscriber", entry[:subscriber_name]
    end

    def test_size
      assert_equal 0, @dlq.size

      3.times do |i|
        message = create_test_message(payload: { order: i })
        @dlq.add(message, error: StandardError.new("error"))
      end

      assert_equal 3, @dlq.size
    end

    def test_empty
      assert_empty @dlq

      @dlq.add(create_test_message, error: StandardError.new("error"))

      refute_empty @dlq
    end

    def test_max_size_enforcement
      dlq = DeadLetterQueue.new(max_size: 3, logger: @logger)

      5.times do |i|
        message = create_test_message(payload: { order: i })
        dlq.add(message, error: StandardError.new("error"))
      end

      assert_equal 3, dlq.size
    end

    def test_enumerable
      3.times do |i|
        message = create_test_message(payload: { order: i })
        @dlq.add(message, error: StandardError.new("error"))
      end

      orders = @dlq.map { |entry| entry[:message].payload[:order] }
      assert_equal [0, 1, 2], orders
    end

    def test_find_by_id
      message = create_test_message
      @dlq.add(message, error: StandardError.new("error"))

      entry = @dlq.find_by_id(message.id)

      assert_equal message.id, entry[:message].id
    end

    def test_find_by_topic
      @dlq.add(create_test_message(topic: "orders.created"), error: StandardError.new("error"))
      @dlq.add(create_test_message(topic: "orders.updated"), error: StandardError.new("error"))
      @dlq.add(create_test_message(topic: "orders.created"), error: StandardError.new("error"))

      entries = @dlq.find_by_topic("orders.created")

      assert_equal 2, entries.size
    end

    def test_find_by_error
      @dlq.add(create_test_message, error: StandardError.new("error"))
      @dlq.add(create_test_message, error: ArgumentError.new("error"))
      @dlq.add(create_test_message, error: StandardError.new("error"))

      entries = @dlq.find_by_error("StandardError")

      assert_equal 2, entries.size
    end

    def test_find_by_subscriber
      @dlq.add(create_test_message, error: StandardError.new("error"), subscriber_name: "sub1")
      @dlq.add(create_test_message, error: StandardError.new("error"), subscriber_name: "sub2")
      @dlq.add(create_test_message, error: StandardError.new("error"), subscriber_name: "sub1")

      entries = @dlq.find_by_subscriber("sub1")

      assert_equal 2, entries.size
    end

    def test_find_by_time_range
      message = create_test_message
      @dlq.add(message, error: StandardError.new("error"))

      entries = @dlq.find_by_time_range(from: Time.now - 60, to: Time.now + 60)

      assert_equal 1, entries.size
    end

    def test_replay_success
      message = create_test_message
      entry = @dlq.add(message, error: StandardError.new("error"))
      processed = nil

      result = @dlq.replay(entry) { |m| processed = m }

      assert result
      assert_equal message.id, processed.id
      assert_empty @dlq
    end

    def test_replay_failure
      message = create_test_message
      entry = @dlq.add(message, error: StandardError.new("error"))

      result = @dlq.replay(entry) { raise "still failing" }

      refute result
      assert_equal 1, @dlq.size
    end

    def test_replay_all
      3.times do |i|
        @dlq.add(create_test_message(payload: { order: i }), error: StandardError.new("error"))
      end

      processed = []
      results = @dlq.replay_all { |m| processed << m }

      assert_equal 3, results[:success]
      assert_equal 0, results[:failed]
      assert_equal 3, processed.size
      assert_empty @dlq
    end

    def test_remove
      message = create_test_message
      entry = @dlq.add(message, error: StandardError.new("error"))

      @dlq.remove(entry)

      assert_empty @dlq
    end

    def test_clear
      3.times { @dlq.add(create_test_message, error: StandardError.new("error")) }

      @dlq.clear

      assert_empty @dlq
    end

    def test_stats
      @dlq.add(create_test_message(topic: "orders.created"), error: StandardError.new("e"), subscriber_name: "s1")
      @dlq.add(create_test_message(topic: "orders.updated"), error: ArgumentError.new("e"), subscriber_name: "s1")
      @dlq.add(create_test_message(topic: "orders.created"), error: StandardError.new("e"), subscriber_name: "s2")

      stats = @dlq.stats

      assert_equal 3, stats[:size]
      assert_equal 100, stats[:max_size]
      assert_equal({ "StandardError" => 2, "ArgumentError" => 1 }, stats[:by_error])
      assert_equal({ "orders.created" => 2, "orders.updated" => 1 }, stats[:by_topic])
      assert_equal({ "s1" => 2, "s2" => 1 }, stats[:by_subscriber])
    end
  end
end
