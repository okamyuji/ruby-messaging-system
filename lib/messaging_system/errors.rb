# frozen_string_literal: true

module MessagingSystem
  class Error < StandardError; end

  # Configuration errors
  class ConfigurationError < Error; end
  class InvalidTopicError < ConfigurationError; end
  class InvalidPayloadError < ConfigurationError; end
  class InvalidPatternError < ConfigurationError; end

  # Operational errors (renamed from RuntimeError to avoid collision with ::RuntimeError)
  class OperationalError < Error; end
  class QueueFullError < OperationalError; end
  class TimeoutError < OperationalError; end
  class ShutdownError < OperationalError; end
  class NotRunningError < OperationalError; end

  # Processing errors
  class ProcessingError < Error; end
  class HandlerError < ProcessingError; end
  class RetryExhaustedError < ProcessingError; end
  class CircuitBreakerOpenError < ProcessingError; end

  # Validation errors
  class ValidationError < Error; end
  class TopicFormatError < ValidationError; end
  class PayloadSizeError < ValidationError; end

  # Deprecation
  class DeprecationError < Error; end
end
