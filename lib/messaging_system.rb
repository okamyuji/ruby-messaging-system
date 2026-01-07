# frozen_string_literal: true

require_relative "messaging_system/version"
require_relative "messaging_system/errors"
require_relative "messaging_system/null_logger"
require_relative "messaging_system/null_metrics"
require_relative "messaging_system/message"
require_relative "messaging_system/topic_matcher"
require_relative "messaging_system/message_queue"
require_relative "messaging_system/worker_pool"
require_relative "messaging_system/circuit_breaker"
require_relative "messaging_system/dead_letter_queue"
require_relative "messaging_system/subscription"
require_relative "messaging_system/subscriber"
require_relative "messaging_system/publisher"
require_relative "messaging_system/message_broker"

module MessagingSystem
  class << self
    def create_broker(**options)
      MessageBroker.new(**options)
    end

    def create_publisher(broker:, **options)
      Publisher.new(broker: broker, **options)
    end

    def create_subscriber(name, broker:, **options)
      Subscriber.new(name, broker: broker, **options)
    end
  end
end
