# frozen_string_literal: true

require "monitor"

module MessagingSystem
  class MessageQueue
    OVERFLOW_BLOCK = :block
    OVERFLOW_DROP_OLDEST = :drop_oldest
    OVERFLOW_REJECT = :reject

    attr_reader :capacity
    attr_reader :overflow_strategy

    def initialize(capacity: 10_000, overflow: OVERFLOW_BLOCK)
      @capacity = capacity
      @overflow_strategy = overflow
      @queue = Queue.new
      @priority_queues = {
        high: Queue.new,
        normal: Queue.new,
        low: Queue.new,
      }
      @lock = Monitor.new
      @size = 0
      @closed = false
    end

    def push(message, priority: :normal)
      raise ShutdownError, "Queue is closed" if @closed

      @lock.synchronize do
        handle_overflow if @size >= @capacity

        target_queue = @priority_queues[priority] || @priority_queues[:normal]
        target_queue << message
        @size += 1
      end

      true
    end

    alias << push
    alias enqueue push

    def pop(timeout: nil)
      return nil if @closed && empty?

      message = pop_by_priority(timeout)
      @lock.synchronize { @size -= 1 } if message
      message
    end

    alias dequeue pop

    def pop_non_blocking
      return nil if empty?

      pop(timeout: 0)
    end

    def size
      @lock.synchronize { @size }
    end

    def empty?
      size.zero?
    end

    def full?
      size >= @capacity
    end

    def close
      @lock.synchronize { @closed = true }
    end

    def closed?
      @closed
    end

    def clear
      @lock.synchronize do
        @priority_queues.each_value(&:clear)
        @size = 0
      end
    end

    def stats
      @lock.synchronize do
        {
          size: @size,
          capacity: @capacity,
          utilization: @size.to_f / @capacity,
          closed: @closed,
          high_priority: queue_size(:high),
          normal_priority: queue_size(:normal),
          low_priority: queue_size(:low),
        }
      end
    end

    private

    def pop_by_priority(timeout)
      start_time = Time.now

      loop do
        [:high, :normal, :low].each do |priority|
          queue = @priority_queues[priority]
          begin
            return queue.pop(true) unless queue.empty?
          rescue ThreadError
            next
          end
        end

        return nil if @closed

        if timeout
          elapsed = Time.now - start_time
          return nil if elapsed >= timeout

          sleep([0.001, timeout - elapsed].min)
        else
          sleep(0.001)
          return nil if @closed && empty?
        end
      end
    end

    def queue_size(priority)
      @priority_queues[priority]&.size || 0
    end

    def handle_overflow
      case @overflow_strategy
      when OVERFLOW_BLOCK
        @lock.new_cond.wait_while { @size >= @capacity && !@closed }
      when OVERFLOW_DROP_OLDEST
        drop_oldest
      when OVERFLOW_REJECT
        raise QueueFullError, "Queue capacity #{@capacity} exceeded"
      end
    end

    def drop_oldest
      [:low, :normal, :high].each do |priority|
        queue = @priority_queues[priority]
        next if queue.empty?

        begin
          queue.pop(true)
          @size -= 1
          break
        rescue ThreadError
          next
        end
      end
    end
  end
end
