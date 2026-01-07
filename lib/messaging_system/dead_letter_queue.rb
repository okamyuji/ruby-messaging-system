# frozen_string_literal: true

require "monitor"

module MessagingSystem
  class DeadLetterQueue
    include Enumerable

    attr_reader :max_size

    def initialize(max_size: 10_000, logger: nil)
      @max_size = max_size
      @logger = logger || NullLogger.new
      @messages = []
      @lock = Monitor.new
    end

    def add(message, error:, subscriber_name: nil)
      entry = {
        message: message,
        error_class: error.class.name,
        error_message: error.message,
        backtrace: error.backtrace&.first(10),
        subscriber_name: subscriber_name,
        failed_at: Time.now,
      }

      @lock.synchronize do
        @messages.shift if @messages.size >= @max_size
        @messages << entry
      end

      @logger.warn("Message #{message.id} moved to DLQ: #{error.message}")
      entry
    end

    alias << add

    def each(&block)
      snapshot = @lock.synchronize { @messages.dup }
      snapshot.each(&block)
    end

    def size
      @lock.synchronize { @messages.size }
    end

    def empty?
      size.zero?
    end

    def clear
      @lock.synchronize { @messages.clear }
    end

    def find_by_id(message_id)
      @lock.synchronize do
        @messages.find { |entry| entry[:message].id == message_id }
      end
    end

    def find_by_topic(topic)
      @lock.synchronize do
        @messages.select { |entry| entry[:message].topic == topic }
      end
    end

    def find_by_error(error_class)
      @lock.synchronize do
        @messages.select { |entry| entry[:error_class] == error_class }
      end
    end

    def find_by_subscriber(subscriber_name)
      @lock.synchronize do
        @messages.select { |entry| entry[:subscriber_name] == subscriber_name }
      end
    end

    def find_by_time_range(from:, to:)
      @lock.synchronize do
        @messages.select do |entry|
          entry[:failed_at].between?(from, to)
        end
      end
    end

    def replay(entry, &handler)
      raise ArgumentError, "Handler block required" unless handler

      message = entry[:message]
      handler.call(message)

      @lock.synchronize do
        @messages.delete(entry)
      end

      @logger.info("Message #{message.id} replayed successfully")
      true
    rescue StandardError => e
      @logger.error("Replay failed for message #{message.id}: #{e.message}")
      false
    end

    def replay_all(filter: nil, &handler)
      entries = filter ? select(&filter) : to_a
      results = { success: 0, failed: 0 }

      entries.each do |entry|
        if replay(entry, &handler)
          results[:success] += 1
        else
          results[:failed] += 1
        end
      end

      results
    end

    def remove(entry)
      @lock.synchronize do
        @messages.delete(entry)
      end
    end

    def stats
      @lock.synchronize do
        {
          size: @messages.size,
          max_size: @max_size,
          by_error: @messages.group_by { |e| e[:error_class] }.transform_values(&:size),
          by_topic: @messages.group_by { |e| e[:message].topic }.transform_values(&:size),
          by_subscriber: @messages.group_by { |e| e[:subscriber_name] }.transform_values(&:size),
        }
      end
    end
  end
end
