# frozen_string_literal: true

require "securerandom"

module MessagingSystem
  class Subscription
    attr_reader :id
    attr_reader :pattern
    attr_reader :handler
    attr_reader :priority
    attr_reader :filter
    attr_reader :created_at

    def initialize(pattern:, handler:, priority: :normal, filter: nil)
      @id = SecureRandom.uuid
      @pattern = pattern
      @handler = handler
      @priority = priority
      @filter = filter
      @created_at = Time.now
      @paused = false
    end

    def call(message)
      return if paused?
      return unless passes_filter?(message)

      handler.call(message)
    end

    def matches?(topic, topic_matcher)
      topic_matcher.matches?(@pattern, topic)
    end

    def pause
      @paused = true
    end

    def resume
      @paused = false
    end

    def paused?
      @paused
    end

    def to_h
      {
        id: @id,
        pattern: @pattern,
        priority: @priority,
        paused: @paused,
        created_at: @created_at,
      }
    end

    private

    def passes_filter?(message)
      return true unless @filter

      @filter.call(message)
    rescue StandardError
      false
    end
  end
end
