#!/usr/bin/env ruby
# frozen_string_literal: true

# Basic Pub/Sub Example
# This example demonstrates simple publish/subscribe messaging

require_relative "../lib/messaging_system"
require "logger"

# Create a logger for visibility
logger = Logger.new($stdout)
logger.level = Logger::INFO

# Create a message broker
broker = MessagingSystem::MessageBroker.new(logger: logger)

# Create subscribers
order_subscriber = MessagingSystem::Subscriber.new(
  "order-processor",
  broker: broker,
  logger: logger,
  async: true,
  worker_count: 2,
)

notification_subscriber = MessagingSystem::Subscriber.new(
  "notification-sender",
  broker: broker,
  logger: logger,
  async: true,
  worker_count: 1,
)

# Subscribe to topics
order_subscriber.subscribe("orders.*") do |message|
  puts "[OrderProcessor] Received: #{message.topic}"
  puts "  Payload: #{message.payload}"
  puts "  Message ID: #{message.id}"
end

notification_subscriber.subscribe("orders.created") do |message|
  puts "[NotificationSender] Sending confirmation for order #{message.payload[:order_id]}"
end

# Give subscribers time to start
sleep 0.2

# Create a publisher
publisher = MessagingSystem::Publisher.new(
  broker: broker,
  name: "order-service",
  logger: logger,
)

# Publish some messages
puts "\n=== Publishing messages ===\n\n"

publisher.publish("orders.created", {
                    order_id: 1001,
                    customer: "John Doe",
                    total: 99.99,
                  })

publisher.publish("orders.updated", {
                    order_id: 1001,
                    status: "processing",
                  })

publisher.publish("orders.shipped", {
                    order_id: 1001,
                    tracking: "ABC123",
                  })

# Wait for processing
sleep 0.5

# Print stats
puts "\n=== Statistics ===\n"
puts "Broker stats: #{broker.stats.slice(:published_count, :routed_count, :subscriber_count)}"
puts "Publisher stats: #{publisher.stats.slice(:published_count)}"

# Graceful shutdown
puts "\n=== Shutting down ===\n"
broker.shutdown(timeout: 5)
puts "Done!"
