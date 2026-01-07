# frozen_string_literal: true

require "monitor"

module MessagingSystem
  class Subscriber
    attr_reader :name
    attr_reader :subscriptions

    def initialize(
      name,
      broker:,
      logger: nil,
      async: true,
      worker_count: 10,
      queue_size: 1_000,
      max_retries: 3,
      retry_delay: 1.0,
      circuit_breaker_threshold: 5,
      circuit_breaker_timeout: 60
    )
      @name = name
      @broker = broker
      @logger = logger || NullLogger.new
      @async = async
      @worker_count = worker_count
      @queue_size = queue_size
      @max_retries = max_retries
      @retry_delay = retry_delay

      @subscriptions = {}
      @lock = Monitor.new
      @running = false
      @paused = false
      @processed_count = 0
      @error_count = 0

      @message_queue = MessageQueue.new(capacity: queue_size)
      @worker_pool = nil
      @circuit_breaker = CircuitBreaker.new(
        name: "subscriber-#{name}",
        failure_threshold: circuit_breaker_threshold,
        timeout: circuit_breaker_timeout,
        logger: @logger,
      )
    end

    def subscribe(pattern, priority: :normal, filter: nil, &handler)
      raise ArgumentError, "Block required" unless handler

      subscription = Subscription.new(
        pattern: pattern,
        handler: handler,
        priority: priority,
        filter: filter,
      )

      @lock.synchronize do
        @subscriptions[subscription.id] = subscription
      end

      @broker.register_subscription(self, subscription)
      start if @async && !@running

      @logger.info("Subscriber '#{@name}' subscribed to '#{pattern}'")
      subscription
    end

    def unsubscribe(pattern_or_subscription)
      @lock.synchronize do
        case pattern_or_subscription
        when Subscription
          @subscriptions.delete(pattern_or_subscription.id)
          @broker.unregister_subscription(self, pattern_or_subscription)
        when String
          to_remove = @subscriptions.values.select { |s| s.pattern == pattern_or_subscription }
          to_remove.each do |sub|
            @subscriptions.delete(sub.id)
            @broker.unregister_subscription(self, sub)
          end
        end
      end
    end

    def receive(message)
      if @async
        @message_queue.push(message, priority: message.priority)
      else
        process_message(message)
      end
    end

    def start
      @lock.synchronize do
        return if @running

        @running = true

        if @async
          @worker_pool = WorkerPool.new(
            size: @worker_count,
            name: "subscriber-#{@name}",
            logger: @logger,
          )
          @worker_pool.start { |msg| process_message(msg) }

          start_dispatcher
        end
      end

      @logger.info("Subscriber '#{@name}' started")
      self
    end

    def shutdown(timeout: 30)
      @lock.synchronize do
        return unless @running

        @running = false
      end

      # Wait for dispatcher to finish processing remaining messages
      @dispatcher_thread&.join(timeout / 2.0)
      @dispatcher_thread&.kill if @dispatcher_thread&.alive?

      # Drain any remaining messages in the queue to the worker pool
      drain_queue

      @message_queue.close
      @worker_pool&.shutdown(timeout: timeout / 2.0)

      @logger.info("Subscriber '#{@name}' shutdown complete")
    end

    def pause
      @paused = true
      @subscriptions.each_value(&:pause)
      @logger.info("Subscriber '#{@name}' paused")
    end

    def resume
      @paused = false
      @subscriptions.each_value(&:resume)
      @logger.info("Subscriber '#{@name}' resumed")
    end

    def paused?
      @paused
    end

    def running?
      @running
    end

    def pending_messages
      @message_queue.size
    end

    def stats
      @lock.synchronize do
        {
          name: @name,
          running: @running,
          paused: @paused,
          async: @async,
          subscription_count: @subscriptions.size,
          pending_messages: pending_messages,
          processed_count: @processed_count,
          error_count: @error_count,
          circuit_breaker: @circuit_breaker.stats,
          worker_pool: @worker_pool&.stats,
        }
      end
    end

    private

    def start_dispatcher
      @dispatcher_thread = Thread.new do
        Thread.current.name = "dispatcher-#{@name}"
        dispatcher_loop
      end
    end

    def dispatcher_loop
      loop do
        break unless @running

        message = @message_queue.pop(timeout: 0.1)
        next unless message

        @worker_pool.submit(message)
      rescue StandardError => e
        @logger.error("Dispatcher error: #{e.message}")
      end
    end

    def process_message(message)
      return if @paused
      return if message.expired?

      @circuit_breaker.call do
        matching_subscriptions(message).each do |subscription|
          execute_handler(subscription, message)
        end
      end

      @lock.synchronize { @processed_count += 1 }
    rescue CircuitBreakerOpenError => e
      @logger.warn("Circuit breaker open for '#{@name}': #{e.message}")
      handle_circuit_breaker_open(message)
    rescue StandardError => e
      @lock.synchronize { @error_count += 1 }
      handle_processing_error(message, e)
    end

    def execute_handler(subscription, message)
      subscription.call(message)
    rescue StandardError => e
      @logger.error("Handler error in subscription #{subscription.id}: #{e.message}")
      raise
    end

    def matching_subscriptions(message)
      topic_matcher = @broker.topic_matcher
      @subscriptions.values.select { |s| s.matches?(message.topic, topic_matcher) }
    end

    def handle_processing_error(message, error)
      @logger.error("Error processing message #{message.id}: #{error.message}")

      # Notify broker of the error
      notify_broker_error(message, error)

      if message.retry_count < @max_retries
        schedule_retry(message)
      else
        move_to_dead_letter_queue(message, error)
      end
    end

    def notify_broker_error(message, error)
      @broker.send(:run_hooks, :on_error, message, error)
    rescue StandardError => e
      @logger.warn("Error notifying broker: #{e.message}")
    end

    def handle_circuit_breaker_open(message)
      move_to_dead_letter_queue(message, CircuitBreakerOpenError.new("Circuit breaker open"))
    end

    def schedule_retry(message)
      retried_message = message.with_retry_increment
      delay = @retry_delay * (2**message.retry_count)

      Thread.new do
        sleep(delay)
        receive(retried_message) if @running
      end

      @logger.info("Scheduled retry #{retried_message.retry_count} for message #{message.id} in #{delay}s")
    end

    def move_to_dead_letter_queue(message, error)
      @broker.dead_letter_queue.add(message, error: error, subscriber_name: @name)
    end

    def drain_queue
      return unless @worker_pool

      while (message = @message_queue.pop(timeout: 0))
        @worker_pool.submit(message)
      end
    end
  end
end
