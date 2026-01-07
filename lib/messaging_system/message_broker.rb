# frozen_string_literal: true

require "monitor"

module MessagingSystem
  class MessageBroker
    attr_reader :logger
    attr_reader :metrics
    attr_reader :topic_matcher
    attr_reader :dead_letter_queue
    attr_reader :test_mode

    def initialize(
      logger: nil,
      metrics: nil,
      test_mode: false,
      max_queue_size: 10_000,
      worker_threads: 10,
      shutdown_timeout: 30
    )
      @logger = logger || NullLogger.new
      @metrics = metrics || NullMetrics.new
      @test_mode = test_mode
      @config = {
        max_queue_size: max_queue_size,
        worker_threads: worker_threads,
        shutdown_timeout: shutdown_timeout,
      }

      @subscribers = {}
      @subscriptions_by_pattern = {}
      @topic_matcher = TopicMatcher.new
      @dead_letter_queue = DeadLetterQueue.new(logger: @logger)
      @lock = Monitor.new
      @running = true

      @published_messages = [] if @test_mode
      @published_count = 0
      @routed_count = 0
      @error_count = 0

      @hooks = {
        on_publish: [],
        on_consume: [],
        on_error: [],
        on_shutdown: [],
      }
    end

    def publish(topic, payload, **options)
      publisher = Publisher.new(broker: self, logger: @logger)
      publisher.publish(topic, payload, **options)
    end

    def subscribe(pattern, subscriber_name: nil, **options, &handler)
      name = subscriber_name || "subscriber-#{SecureRandom.uuid[0..7]}"
      subscriber = Subscriber.new(
        name,
        broker: self,
        logger: @logger,
        async: !@test_mode,
        **options,
      )
      subscriber.subscribe(pattern, &handler)
      subscriber
    end

    def route(message)
      raise ShutdownError, "Broker is not running" unless @running

      @lock.synchronize { @published_count += 1 }
      @published_messages << message if @test_mode

      run_hooks(:on_publish, message)
      @metrics.increment("messages.published")

      matching_subscribers = find_matching_subscribers(message.topic)

      if matching_subscribers.empty?
        @logger.debug("No subscribers for topic '#{message.topic}'")
        return
      end

      if @test_mode
        deliver_sync(message, matching_subscribers)
      else
        deliver_async(message, matching_subscribers)
      end

      @lock.synchronize { @routed_count += 1 }
      @metrics.increment("messages.routed")
    end

    def register_subscription(subscriber, subscription)
      @lock.synchronize do
        @subscribers[subscriber.name] = subscriber

        @subscriptions_by_pattern[subscription.pattern] ||= []
        @subscriptions_by_pattern[subscription.pattern] << {
          subscriber: subscriber,
          subscription: subscription,
        }
      end

      @logger.info("Registered subscription '#{subscription.pattern}' for '#{subscriber.name}'")
    end

    def unregister_subscription(subscriber, subscription)
      @lock.synchronize do
        entries = @subscriptions_by_pattern[subscription.pattern]
        entries&.reject! { |e| e[:subscription].id == subscription.id }

        @subscribers.delete(subscriber.name) if subscriber.subscriptions.empty?
      end

      @logger.info("Unregistered subscription '#{subscription.pattern}' for '#{subscriber.name}'")
    end

    def shutdown(timeout: nil)
      timeout ||= @config[:shutdown_timeout]

      @lock.synchronize do
        return unless @running

        @running = false
      end

      run_hooks(:on_shutdown)

      @subscribers.each_value do |subscriber|
        subscriber.shutdown(timeout: timeout)
      end

      @logger.info("MessageBroker shutdown complete")
    end

    def reset!
      @lock.synchronize do
        @subscribers.each_value(&:shutdown)
        @subscribers.clear
        @subscriptions_by_pattern.clear
        @published_messages&.clear
        @dead_letter_queue.clear
        @topic_matcher.clear_cache
        @published_count = 0
        @routed_count = 0
        @error_count = 0
        @running = true
      end
    end

    def running?
      @running
    end

    def subscriber_count
      @lock.synchronize { @subscribers.size }
    end

    def subscription_count
      @lock.synchronize do
        @subscriptions_by_pattern.values.flatten.size
      end
    end

    def published_messages
      raise "published_messages only available in test mode" unless @test_mode

      @published_messages.dup
    end

    def on_publish(&block)
      @hooks[:on_publish] << block
    end

    def on_consume(&block)
      @hooks[:on_consume] << block
    end

    def on_error(&block)
      @hooks[:on_error] << block
    end

    def on_shutdown(&block)
      @hooks[:on_shutdown] << block
    end

    def backpressure?(_topic = nil)
      @subscribers.values.any? do |subscriber|
        subscriber.pending_messages > @config[:max_queue_size] * 0.8
      end
    end

    def stats
      @lock.synchronize do
        {
          running: @running,
          test_mode: @test_mode,
          subscriber_count: @subscribers.size,
          subscription_count: subscription_count,
          published_count: @published_count,
          routed_count: @routed_count,
          error_count: @error_count,
          dead_letter_queue_size: @dead_letter_queue.size,
          config: @config,
          subscribers: @subscribers.transform_values(&:stats),
        }
      end
    end

    def health
      {
        status: @running ? "healthy" : "stopped",
        broker: "ok",
        workers: @subscribers.values.all?(&:running?) ? "ok" : "degraded",
        queue_depth: backpressure? ? "high" : "ok",
      }
    end

    private

    def find_matching_subscribers(topic)
      results = []

      @lock.synchronize do
        @subscriptions_by_pattern.each do |pattern, entries|
          next unless @topic_matcher.matches?(pattern, topic)

          entries.each do |entry|
            results << entry[:subscriber] unless entry[:subscription].paused?
          end
        end
      end

      results.uniq
    end

    def deliver_sync(message, subscribers)
      subscribers.each do |subscriber|
        subscriber.receive(message)
        run_hooks(:on_consume, message)
      rescue StandardError => e
        handle_delivery_error(message, subscriber, e)
      end
    end

    def deliver_async(message, subscribers)
      subscribers.each do |subscriber|
        subscriber.receive(message)
        run_hooks(:on_consume, message)
      rescue StandardError => e
        handle_delivery_error(message, subscriber, e)
      end
    end

    def handle_delivery_error(message, subscriber, error)
      @lock.synchronize { @error_count += 1 }
      @metrics.increment("messages.errors")
      @logger.error("Delivery error for message #{message.id} to '#{subscriber.name}': #{error.message}")
      run_hooks(:on_error, message, error)
    end

    def run_hooks(hook_type, *args)
      @hooks[hook_type].each do |hook|
        hook.call(*args)
      rescue StandardError => e
        @logger.warn("Hook error (#{hook_type}): #{e.message}")
      end
    end
  end
end
