# frozen_string_literal: true

require "test_helper"

module MessagingSystem
  class MessageQueueTest < Minitest::Test
    include TestHelpers

    def setup
      @queue = MessageQueue.new(capacity: 100)
    end

    def teardown
      @queue.close
    end

    def test_push_and_pop
      message = create_test_message
      @queue.push(message)

      popped = @queue.pop(timeout: 1)

      assert_equal message, popped
    end

    def test_fifo_ordering
      messages = 3.times.map { |i| create_test_message(payload: { order: i }) }
      messages.each { |m| @queue.push(m) }

      popped = 3.times.map { @queue.pop(timeout: 1) }

      assert_equal [0, 1, 2], popped.map { |m| m.payload[:order] }
    end

    def test_priority_ordering
      low = create_test_message(payload: { priority: "low" })
      normal = create_test_message(payload: { priority: "normal" })
      high = create_test_message(payload: { priority: "high" })

      @queue.push(low, priority: :low)
      @queue.push(normal, priority: :normal)
      @queue.push(high, priority: :high)

      first = @queue.pop(timeout: 1)
      second = @queue.pop(timeout: 1)
      third = @queue.pop(timeout: 1)

      assert_equal "high", first.payload[:priority]
      assert_equal "normal", second.payload[:priority]
      assert_equal "low", third.payload[:priority]
    end

    def test_size
      assert_equal 0, @queue.size

      3.times { @queue.push(create_test_message) }

      assert_equal 3, @queue.size
    end

    def test_empty
      assert_empty @queue

      @queue.push(create_test_message)

      refute_empty @queue
    end

    def test_full
      queue = MessageQueue.new(capacity: 2, overflow: :reject)

      queue.push(create_test_message)
      refute queue.full?

      queue.push(create_test_message)
      assert queue.full?
    end

    def test_overflow_reject
      queue = MessageQueue.new(capacity: 1, overflow: :reject)
      queue.push(create_test_message)

      assert_raises(QueueFullError) do
        queue.push(create_test_message)
      end
    end

    def test_overflow_drop_oldest
      queue = MessageQueue.new(capacity: 2, overflow: :drop_oldest)

      first = create_test_message(payload: { order: 1 })
      second = create_test_message(payload: { order: 2 })
      third = create_test_message(payload: { order: 3 })

      queue.push(first)
      queue.push(second)
      queue.push(third)

      assert_equal 2, queue.size
    end

    def test_non_blocking_pop
      assert_nil @queue.pop_non_blocking

      @queue.push(create_test_message)

      refute_nil @queue.pop_non_blocking
    end

    def test_close
      @queue.close

      assert @queue.closed?
      assert_raises(ShutdownError) { @queue.push(create_test_message) }
    end

    def test_clear
      3.times { @queue.push(create_test_message) }
      @queue.clear

      assert_empty @queue
    end

    def test_stats
      @queue.push(create_test_message, priority: :high)
      @queue.push(create_test_message, priority: :normal)
      @queue.push(create_test_message, priority: :low)

      stats = @queue.stats

      assert_equal 3, stats[:size]
      assert_equal 100, stats[:capacity]
      assert_equal 1, stats[:high_priority]
      assert_equal 1, stats[:normal_priority]
      assert_equal 1, stats[:low_priority]
    end

    def test_aliases
      message = create_test_message

      @queue << message
      assert_equal 1, @queue.size

      @queue.enqueue(create_test_message)
      assert_equal 2, @queue.size

      @queue.dequeue
      assert_equal 1, @queue.size
    end

    def test_thread_safe_operations
      threads = 10.times.map do
        Thread.new do
          10.times { @queue.push(create_test_message) }
        end
      end

      threads.each(&:join)

      assert_equal 100, @queue.size
    end
  end
end
