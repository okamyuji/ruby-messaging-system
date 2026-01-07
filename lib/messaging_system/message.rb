# frozen_string_literal: true

require "securerandom"
require "json"
require "time"

module MessagingSystem
  class Message
    MAX_TOPIC_LENGTH = 255
    MAX_PAYLOAD_SIZE = 65_536 # 64KB
    TOPIC_PATTERN = /\A[a-zA-Z0-9._-]+\z/

    attr_reader :id
    attr_reader :topic
    attr_reader :payload
    attr_reader :headers
    attr_reader :created_at
    attr_reader :expires_at

    def initialize(topic:, payload:, headers: {}, id: nil, created_at: nil, expires_at: nil)
      @id = id || SecureRandom.uuid
      @topic = validate_and_freeze_topic(topic)
      @payload = validate_and_freeze_payload(payload)
      @created_at = (created_at || Time.now).freeze
      @expires_at = expires_at&.freeze
      @headers = build_headers(headers).freeze
      freeze
    end

    def expired?
      return false unless @expires_at

      Time.now > @expires_at
    end

    def retry_count
      @headers[:retry_count] || 0
    end

    def correlation_id
      @headers[:correlation_id]
    end

    def priority
      @headers[:priority] || :normal
    end

    def with_retry_increment
      new_headers = @headers.dup
      new_headers[:retry_count] = retry_count + 1
      Message.new(
        topic: @topic,
        payload: deep_dup(@payload),
        headers: new_headers,
        id: @id,
        created_at: @created_at,
        expires_at: @expires_at,
      )
    end

    def with_headers(additional_headers)
      new_headers = @headers.merge(additional_headers)
      Message.new(
        topic: @topic,
        payload: deep_dup(@payload),
        headers: new_headers,
        id: @id,
        created_at: @created_at,
        expires_at: @expires_at,
      )
    end

    def to_h
      {
        id: @id,
        topic: @topic,
        payload: @payload,
        headers: @headers,
        created_at: @created_at.iso8601,
        expires_at: @expires_at&.iso8601,
      }
    end

    def to_json(*args)
      to_h.to_json(*args)
    end

    def self.from_json(json_string)
      data = JSON.parse(json_string, symbolize_names: true)
      new(
        topic: data[:topic],
        payload: data[:payload],
        headers: data[:headers] || {},
        id: data[:id],
        created_at: data[:created_at] ? Time.parse(data[:created_at]) : nil,
        expires_at: data[:expires_at] ? Time.parse(data[:expires_at]) : nil,
      )
    end

    def ==(other)
      return false unless other.is_a?(Message)

      @id == other.id
    end

    alias eql? ==

    def hash
      @id.hash
    end

    private

    def validate_and_freeze_topic(topic)
      raise InvalidTopicError, "Topic cannot be nil" if topic.nil?
      raise InvalidTopicError, "Topic cannot be empty" if topic.empty?
      raise InvalidTopicError, "Topic exceeds maximum length of #{MAX_TOPIC_LENGTH}" if topic.length > MAX_TOPIC_LENGTH
      raise TopicFormatError, "Topic contains invalid characters: #{topic}" unless topic.match?(TOPIC_PATTERN)

      topic.frozen? ? topic : topic.dup.freeze
    end

    def validate_and_freeze_payload(payload)
      raise InvalidPayloadError, "Payload cannot be nil" if payload.nil?

      json_size = payload.to_json.bytesize
      if json_size > MAX_PAYLOAD_SIZE
        raise PayloadSizeError, "Payload size #{json_size} exceeds maximum of #{MAX_PAYLOAD_SIZE} bytes"
      end

      deep_freeze(deep_dup(payload))
    end

    def build_headers(headers)
      default_headers.merge(normalize_headers(headers))
    end

    def default_headers
      {
        timestamp: @created_at.to_i,
        correlation_id: @id,
        retry_count: 0,
        priority: :normal,
      }
    end

    def normalize_headers(headers)
      headers.transform_keys(&:to_sym)
    end

    def deep_freeze(obj)
      case obj
      when Hash
        obj.each { |k, v| obj[k] = deep_freeze(v) }
        obj.freeze
      when Array
        obj.map! { |v| deep_freeze(v) }
        obj.freeze
      when String
        obj.frozen? ? obj : obj.dup.freeze
      else
        begin
          obj.freeze
        rescue FrozenError, TypeError
          obj
        end
      end
    end

    def deep_dup(obj)
      case obj
      when Hash
        obj.transform_values { |v| deep_dup(v) }
      when Array
        obj.map { |v| deep_dup(v) }
      when String
        obj.dup
      else
        obj
      end
    end
  end
end
