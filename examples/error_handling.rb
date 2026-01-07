#!/usr/bin/env ruby
# frozen_string_literal: true

# Error Handling Example
# This example demonstrates retry logic, circuit breaker, and dead letter queue

require_relative "../lib/messaging_system"
require "logger"

logger = Logger.new($stdout)
logger.level = Logger::INFO

broker = MessagingSystem::MessageBroker.new(logger: logger)

# Track processing attempts
attempts = Hash.new(0)

# Create a subscriber with retry configuration
subscriber = MessagingSystem::Subscriber.new(
  "order-processor",
  broker: broker,
  logger: logger,
  async: false, # Sync mode for easier demonstration
  max_retries: 3,
  retry_delay: 0.1,
  circuit_breaker_threshold: 5,
  circuit_breaker_timeout: 10,
)

subscriber.subscribe("orders.*") do |message|
  order_id = message.payload[:order_id]
  attempts[order_id] += 1

  puts "[Attempt #{attempts[order_id]}] Processing order #{order_id}"

  # Simulate failures for specific orders
  case order_id
  when 1
    # Always succeeds
    puts "  ✓ Order #{order_id} processed successfully"
  when 2
    # Fails twice, then succeeds
    if attempts[order_id] < 3
      puts "  ✗ Temporary failure for order #{order_id}"
      raise "Temporary database error"
    else
      puts "  ✓ Order #{order_id} processed on retry"
    end
  when 3
    # Always fails
    puts "  ✗ Permanent failure for order #{order_id}"
    raise "Invalid order data"
  end
end

# Set up error hook
broker.on_error do |message, error|
  puts "[ERROR HOOK] Message #{message.id} failed: #{error.message}"
end

publisher = MessagingSystem::Publisher.new(broker: broker, name: "order-service")

puts "\n=== Publishing orders ===\n\n"

# Order 1: Will succeed immediately
publisher.publish("orders.created", { order_id: 1 })

# Order 2: Will fail twice, then succeed
publisher.publish("orders.created", { order_id: 2 })

# Wait for retries
sleep 0.5

# Order 3: Will fail all retries and go to DLQ
publisher.publish("orders.created", { order_id: 3 })

# Wait for retries
sleep 0.5

# Check dead letter queue
puts "\n=== Dead Letter Queue ===\n"
dlq = broker.dead_letter_queue

if dlq.empty?
  puts "DLQ is empty"
else
  puts "DLQ contains #{dlq.size} message(s):"
  dlq.each do |entry|
    puts "  - Order #{entry[:message].payload[:order_id]}"
    puts "    Error: #{entry[:error_class]}: #{entry[:error_message]}"
    puts "    Failed at: #{entry[:failed_at]}"
  end
end

# Circuit breaker demonstration
puts "\n=== Circuit Breaker Demo ===\n"

circuit_breaker = MessagingSystem::CircuitBreaker.new(
  name: "payment-service",
  failure_threshold: 3,
  success_threshold: 2,
  timeout: 5,
  logger: logger,
)

puts "Initial state: #{circuit_breaker.state}"

# Simulate failures
5.times do |i|
  circuit_breaker.call do
    raise "Payment service unavailable"
  end
rescue MessagingSystem::CircuitBreakerOpenError
  puts "  Request #{i + 1}: Circuit breaker is OPEN, request rejected"
rescue StandardError => e
  puts "  Request #{i + 1}: Failed with '#{e.message}'"
end

puts "Final state: #{circuit_breaker.state}"
puts "Stats: #{circuit_breaker.stats.slice(:failure_count, :state)}"

broker.shutdown(timeout: 5)
puts "\nDone!"
