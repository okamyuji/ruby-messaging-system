# frozen_string_literal: true

require "test_helper"

module MessagingSystem
  class SubscriptionTest < Minitest::Test
    include TestHelpers

    def test_creates_with_pattern_and_handler
      handler = ->(msg) { msg }
      subscription = Subscription.new(pattern: "orders.*", handler: handler)

      assert_match(/\A[0-9a-f-]{36}\z/, subscription.id)
      assert_equal "orders.*", subscription.pattern
      assert_equal :normal, subscription.priority
    end

    def test_call_invokes_handler
      received = nil
      handler = ->(msg) { received = msg }
      subscription = Subscription.new(pattern: "test", handler: handler)

      message = create_test_message
      subscription.call(message)

      assert_equal message, received
    end

    def test_call_skips_when_paused
      received = nil
      handler = ->(msg) { received = msg }
      subscription = Subscription.new(pattern: "test", handler: handler)

      subscription.pause
      subscription.call(create_test_message)

      assert_nil received
    end

    def test_matches_with_topic_matcher
      subscription = Subscription.new(pattern: "orders.*", handler: ->(_msg) {})
      matcher = TopicMatcher.new

      assert subscription.matches?("orders.created", matcher)
      refute subscription.matches?("users.created", matcher)
    end

    def test_pause_and_resume
      subscription = Subscription.new(pattern: "test", handler: ->(_msg) {})

      refute subscription.paused?

      subscription.pause
      assert subscription.paused?

      subscription.resume
      refute subscription.paused?
    end

    def test_filter
      handler = ->(_msg) {}
      filter = ->(msg) { msg.payload[:important] }
      Subscription.new(pattern: "test", handler: handler, filter: filter)

      received = []
      subscription = Subscription.new(
        pattern: "test",
        handler: ->(msg) { received << msg },
        filter: filter,
      )

      subscription.call(create_test_message(payload: { important: true }))
      subscription.call(create_test_message(payload: { important: false }))

      assert_equal 1, received.size
    end

    def test_filter_error_returns_false
      handler = ->(msg) { msg }
      filter = ->(_msg) { raise "filter error" }
      Subscription.new(pattern: "test", handler: handler, filter: filter)

      received = nil
      subscription = Subscription.new(
        pattern: "test",
        handler: ->(msg) { received = msg },
        filter: filter,
      )

      subscription.call(create_test_message)

      assert_nil received
    end

    def test_to_h
      subscription = Subscription.new(pattern: "orders.*", handler: ->(_msg) {}, priority: :high)

      hash = subscription.to_h

      assert_equal subscription.id, hash[:id]
      assert_equal "orders.*", hash[:pattern]
      assert_equal :high, hash[:priority]
      refute hash[:paused]
    end

    def test_priority
      high = Subscription.new(pattern: "test", handler: ->(_msg) {}, priority: :high)
      normal = Subscription.new(pattern: "test", handler: ->(_msg) {}, priority: :normal)
      low = Subscription.new(pattern: "test", handler: ->(_msg) {}, priority: :low)

      assert_equal :high, high.priority
      assert_equal :normal, normal.priority
      assert_equal :low, low.priority
    end
  end
end
