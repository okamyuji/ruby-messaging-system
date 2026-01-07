# frozen_string_literal: true

require "test_helper"

module MessagingSystem
  class MessageTest < Minitest::Test
    def test_creates_message_with_required_attributes
      message = Message.new(topic: "orders.created", payload: { order_id: 123 })

      assert_match(/\A[0-9a-f-]{36}\z/, message.id)
      assert_equal "orders.created", message.topic
      assert_equal({ order_id: 123 }, message.payload)
      assert_instance_of Time, message.created_at
    end

    def test_generates_unique_ids
      messages = 100.times.map { Message.new(topic: "test", payload: {}) }
      ids = messages.map(&:id)

      assert_equal ids.uniq.size, ids.size
    end

    def test_message_is_immutable
      message = Message.new(topic: "test", payload: { data: "value" })

      assert message.frozen?
      assert_raises(FrozenError) { message.instance_variable_set(:@topic, "changed") }
    end

    def test_payload_is_deeply_frozen
      message = Message.new(topic: "test", payload: { nested: { data: "value" } })

      assert message.payload.frozen?
      assert message.payload[:nested].frozen?
    end

    def test_default_headers
      message = Message.new(topic: "test", payload: {})

      assert_equal message.id, message.headers[:correlation_id]
      assert_equal 0, message.headers[:retry_count]
      assert_equal :normal, message.headers[:priority]
      assert_instance_of Integer, message.headers[:timestamp]
    end

    def test_custom_headers
      message = Message.new(
        topic: "test",
        payload: {},
        headers: { custom: "value", priority: :high },
      )

      assert_equal "value", message.headers[:custom]
      assert_equal :high, message.headers[:priority]
    end

    def test_rejects_nil_topic
      assert_raises(InvalidTopicError) do
        Message.new(topic: nil, payload: {})
      end
    end

    def test_rejects_empty_topic
      assert_raises(InvalidTopicError) do
        Message.new(topic: "", payload: {})
      end
    end

    def test_rejects_too_long_topic
      long_topic = "a" * 256

      assert_raises(InvalidTopicError) do
        Message.new(topic: long_topic, payload: {})
      end
    end

    def test_rejects_invalid_topic_format
      assert_raises(TopicFormatError) do
        Message.new(topic: "invalid topic!", payload: {})
      end
    end

    def test_accepts_valid_topic_formats
      valid_topics = ["orders", "orders.created", "orders-v2", "orders_v2", "ORDERS.CREATED"]

      valid_topics.each do |topic|
        message = Message.new(topic: topic, payload: {})
        assert_equal topic, message.topic
      end
    end

    def test_rejects_nil_payload
      assert_raises(InvalidPayloadError) do
        Message.new(topic: "test", payload: nil)
      end
    end

    def test_rejects_oversized_payload
      large_payload = { data: "x" * 100_000 }

      assert_raises(PayloadSizeError) do
        Message.new(topic: "test", payload: large_payload)
      end
    end

    def test_expires_at
      expires = Time.now + 3600
      message = Message.new(topic: "test", payload: {}, expires_at: expires)

      assert_equal expires.to_i, message.expires_at.to_i
      refute message.expired?
    end

    def test_expired_message
      expires = Time.now - 1
      message = Message.new(topic: "test", payload: {}, expires_at: expires)

      assert message.expired?
    end

    def test_with_retry_increment
      message = Message.new(topic: "test", payload: { data: 1 })
      retried = message.with_retry_increment

      assert_equal 0, message.retry_count
      assert_equal 1, retried.retry_count
      assert_equal message.id, retried.id
      assert_equal message.topic, retried.topic
    end

    def test_with_headers
      message = Message.new(topic: "test", payload: {})
      updated = message.with_headers(custom: "value")

      assert_equal "value", updated.headers[:custom]
      refute_same message, updated
    end

    def test_to_h
      message = Message.new(topic: "test", payload: { data: 1 })
      hash = message.to_h

      assert_equal message.id, hash[:id]
      assert_equal "test", hash[:topic]
      assert_equal({ data: 1 }, hash[:payload])
      assert_includes hash[:created_at], "T"
    end

    def test_to_json
      message = Message.new(topic: "test", payload: { data: 1 })
      json = message.to_json

      parsed = JSON.parse(json, symbolize_names: true)
      assert_equal message.id, parsed[:id]
      assert_equal "test", parsed[:topic]
    end

    def test_from_json
      original = Message.new(topic: "test", payload: { data: 1 })
      json = original.to_json
      restored = Message.from_json(json)

      assert_equal original.id, restored.id
      assert_equal original.topic, restored.topic
      assert_equal original.payload, restored.payload
    end

    def test_equality
      message1 = Message.new(topic: "test", payload: {}, id: "same-id")
      message2 = Message.new(topic: "test", payload: {}, id: "same-id")
      message3 = Message.new(topic: "test", payload: {}, id: "different-id")

      assert_equal message1, message2
      refute_equal message1, message3
    end

    def test_hash_for_set_usage
      message1 = Message.new(topic: "test", payload: {}, id: "same-id")
      message2 = Message.new(topic: "test", payload: {}, id: "same-id")

      set = Set.new([message1, message2])
      assert_equal 1, set.size
    end

    def test_correlation_id_accessor
      message = Message.new(topic: "test", payload: {})

      assert_equal message.id, message.correlation_id
    end

    def test_priority_accessor
      message = Message.new(topic: "test", payload: {}, headers: { priority: :high })

      assert_equal :high, message.priority
    end

    # Boundary value tests for MAX_TOPIC_LENGTH (255)
    def test_accepts_topic_at_max_length
      max_length_topic = "a" * 255
      message = Message.new(topic: max_length_topic, payload: {})

      assert_equal 255, message.topic.length
    end

    def test_rejects_topic_one_over_max_length
      over_max_topic = "a" * 256

      assert_raises(InvalidTopicError) do
        Message.new(topic: over_max_topic, payload: {})
      end
    end

    # Boundary value tests for MAX_PAYLOAD_SIZE (64KB = 65536 bytes)
    def test_accepts_payload_near_max_size
      # Create a payload that is just under the limit when serialized to JSON
      # Account for JSON overhead: {"d":"..."} = 7 chars overhead
      data_size = 65_536 - 10 # Leave some room for JSON overhead
      near_max_payload = { d: "x" * data_size }

      # This should not raise if under limit
      skip unless near_max_payload.to_json.bytesize <= 65_536

      message = Message.new(topic: "test", payload: near_max_payload)
      assert_operator message.payload[:d].length, :>, 0
    end

    def test_rejects_payload_over_max_size
      # Create a payload that definitely exceeds 64KB
      over_max_payload = { d: "x" * 70_000 }

      assert_raises(PayloadSizeError) do
        Message.new(topic: "test", payload: over_max_payload)
      end
    end

    # Edge case: single character topic
    def test_accepts_single_character_topic
      message = Message.new(topic: "a", payload: {})

      assert_equal "a", message.topic
    end

    # Edge case: empty hash payload
    def test_accepts_empty_hash_payload
      message = Message.new(topic: "test", payload: {})

      assert_equal({}, message.payload)
    end
  end
end
