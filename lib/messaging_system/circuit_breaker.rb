# frozen_string_literal: true

require "monitor"

module MessagingSystem
  class CircuitBreaker
    STATE_CLOSED = :closed
    STATE_OPEN = :open
    STATE_HALF_OPEN = :half_open

    attr_reader :state
    attr_reader :failure_count
    attr_reader :success_count
    attr_reader :name

    def initialize(
      name:,
      failure_threshold: 5,
      success_threshold: 3,
      timeout: 60,
      logger: nil,
      on_state_change: nil
    )
      @name = name
      @failure_threshold = failure_threshold
      @success_threshold = success_threshold
      @timeout = timeout
      @logger = logger || NullLogger.new
      @on_state_change = on_state_change

      @lock = Monitor.new
      @state = STATE_CLOSED
      @failure_count = 0
      @success_count = 0
      @last_failure_time = nil
    end

    def call(&block)
      check_state_transition

      case @state
      when STATE_OPEN
        raise CircuitBreakerOpenError, "Circuit breaker '#{@name}' is open"
      when STATE_HALF_OPEN, STATE_CLOSED
        execute_with_tracking(&block)
      end
    end

    def open?
      @state == STATE_OPEN
    end

    def closed?
      @state == STATE_CLOSED
    end

    def half_open?
      @state == STATE_HALF_OPEN
    end

    def reset
      @lock.synchronize do
        old_state = @state
        @state = STATE_CLOSED
        @failure_count = 0
        @success_count = 0
        @last_failure_time = nil
        notify_state_change(old_state, STATE_CLOSED) if old_state != STATE_CLOSED
      end
    end

    def force_open
      @lock.synchronize do
        old_state = @state
        @state = STATE_OPEN
        @last_failure_time = Time.now
        notify_state_change(old_state, STATE_OPEN) if old_state != STATE_OPEN
      end
    end

    def stats
      @lock.synchronize do
        {
          name: @name,
          state: @state,
          failure_count: @failure_count,
          success_count: @success_count,
          failure_threshold: @failure_threshold,
          success_threshold: @success_threshold,
          timeout: @timeout,
          last_failure_time: @last_failure_time,
        }
      end
    end

    private

    def check_state_transition
      @lock.synchronize do
        return unless @state == STATE_OPEN && timeout_expired?

        transition_to(STATE_HALF_OPEN)
      end
    end

    def execute_with_tracking
      result = yield
      record_success
      result
    rescue StandardError
      record_failure
      raise
    end

    def record_success
      @lock.synchronize do
        @success_count += 1

        transition_to(STATE_CLOSED) if @state == STATE_HALF_OPEN && @success_count >= @success_threshold
      end
    end

    def record_failure
      @lock.synchronize do
        @failure_count += 1
        @last_failure_time = Time.now

        case @state
        when STATE_CLOSED
          transition_to(STATE_OPEN) if @failure_count >= @failure_threshold
        when STATE_HALF_OPEN
          transition_to(STATE_OPEN)
        end
      end
    end

    def transition_to(new_state)
      old_state = @state
      @state = new_state

      case new_state
      when STATE_CLOSED
        @failure_count = 0
        @success_count = 0
      when STATE_HALF_OPEN
        @success_count = 0
      end

      @logger.info("Circuit breaker '#{@name}' transitioned from #{old_state} to #{new_state}")
      notify_state_change(old_state, new_state)
    end

    def timeout_expired?
      return true unless @last_failure_time

      Time.now - @last_failure_time >= @timeout
    end

    def notify_state_change(old_state, new_state)
      @on_state_change&.call(old_state, new_state)
    end
  end
end
