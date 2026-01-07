# frozen_string_literal: true

require "monitor"

module MessagingSystem
  class Publisher
    attr_reader :name

    def initialize(broker:, name: nil, logger: nil, default_priority: :normal)
      @broker = broker
      @name = name || "publisher-#{SecureRandom.uuid[0..7]}"
      @logger = logger || NullLogger.new
      @default_priority = default_priority
      @lock = Monitor.new
      @published_count = 0
      @error_count = 0
      @hooks = { before_publish: [], after_publish: [] }
    end

    def publish(topic, payload, priority: nil, headers: {}, ttl: nil)
      priority ||= @default_priority
      expires_at = ttl ? Time.now + ttl : nil

      message = build_message(topic, payload, priority, headers, expires_at)

      run_hooks(:before_publish, message)
      @broker.route(message)
      run_hooks(:after_publish, message)

      @lock.synchronize { @published_count += 1 }
      @logger.debug("Published message #{message.id} to '#{topic}'")

      message
    rescue StandardError => e
      @lock.synchronize { @error_count += 1 }
      @logger.error("Failed to publish to '#{topic}': #{e.message}")
      raise
    end

    def publish_batch(messages_data)
      results = { success: [], failed: [] }

      messages_data.each do |data|
        message = publish(
          data[:topic],
          data[:payload],
          priority: data[:priority],
          headers: data[:headers] || {},
          ttl: data[:ttl],
        )
        results[:success] << message
      rescue StandardError => e
        results[:failed] << { data: data, error: e }
      end

      results
    end

    def on_before_publish(&block)
      @hooks[:before_publish] << block
    end

    def on_after_publish(&block)
      @hooks[:after_publish] << block
    end

    def stats
      @lock.synchronize do
        {
          name: @name,
          published_count: @published_count,
          error_count: @error_count,
          default_priority: @default_priority,
        }
      end
    end

    private

    def build_message(topic, payload, priority, headers, expires_at)
      Message.new(
        topic: topic,
        payload: payload,
        headers: headers.merge(
          priority: priority,
          publisher: @name,
        ),
        expires_at: expires_at,
      )
    end

    def run_hooks(hook_type, message)
      @hooks[hook_type].each do |hook|
        hook.call(message)
      rescue StandardError => e
        @logger.warn("Hook error (#{hook_type}): #{e.message}")
      end
    end
  end
end
