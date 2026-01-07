# frozen_string_literal: true

require "timeout"

if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start do
    add_filter "/test/"
    add_group "Core", "lib/messaging_system"
  end
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "messaging_system"
require "minitest/autorun"
require "minitest/reporters"

Minitest::Reporters.use! [Minitest::Reporters::SpecReporter.new]

module MessagingSystem
  module TestHelpers
    def setup_test_broker(**options)
      @broker = MessageBroker.new(test_mode: true, **options)
    end

    def teardown_test_broker
      @broker&.reset!
    end

    def assert_message_published(broker, topic, payload = nil)
      messages = broker.published_messages.select { |m| m.topic == topic }
      assert messages.any?, "Expected message with topic '#{topic}' to be published"

      return unless payload

      assert messages.any? { |m| m.payload == payload },
             "Expected message with payload #{payload}"
    end

    def assert_message_not_published(broker, topic)
      messages = broker.published_messages.select { |m| m.topic == topic }
      assert_empty messages, "Expected no messages with topic '#{topic}'"
    end

    def wait_for_condition(timeout: 1.0, interval: 0.01)
      deadline = Time.now + timeout
      until yield
        return false if Time.now > deadline

        sleep(interval)
      end
      true
    end

    def create_test_message(topic: "test.topic", payload: { data: "test" }, **options)
      Message.new(topic: topic, payload: payload, **options)
    end
  end

  class MockLogger
    attr_reader :messages

    def initialize
      @messages = []
    end

    def debug(msg = nil, &block)
      log(:debug, msg || block&.call)
    end

    def info(msg = nil, &block)
      log(:info, msg || block&.call)
    end

    def warn(msg = nil, &block)
      log(:warn, msg || block&.call)
    end

    def error(msg = nil, &block)
      log(:error, msg || block&.call)
    end

    def fatal(msg = nil, &block)
      log(:fatal, msg || block&.call)
    end

    def level
      0
    end

    def level=(_level); end

    def clear
      @messages.clear
    end

    def messages_at(level)
      @messages.select { |m| m[:level] == level }
    end

    private

    def log(level, message)
      @messages << { level: level, message: message, time: Time.now }
    end
  end

  class MockMetrics
    attr_reader :data

    def initialize
      @data = Hash.new(0)
    end

    def increment(key, value = 1)
      @data[key] += value
    end

    def decrement(key, value = 1)
      @data[key] -= value
    end

    def gauge(key, value)
      @data[key] = value
    end

    def histogram(key, value)
      @data["#{key}.values"] ||= []
      @data["#{key}.values"] << value
    end

    def timing(key, value)
      histogram(key, value)
    end

    def clear
      @data.clear
    end
  end

  class HandlerStub
    attr_reader :called_count
    attr_reader :received_messages
    attr_reader :errors

    def initialize(&block)
      @called_count = 0
      @received_messages = []
      @errors = []
      @custom_handler = block
    end

    def call(message)
      @called_count += 1
      @received_messages << message
      @custom_handler&.call(message)
    rescue StandardError => e
      @errors << e
      raise
    end

    def called_with?(payload)
      @received_messages.any? { |m| m.payload == payload }
    end

    def last_message
      @received_messages.last
    end

    def reset
      @called_count = 0
      @received_messages.clear
      @errors.clear
    end
  end
end
