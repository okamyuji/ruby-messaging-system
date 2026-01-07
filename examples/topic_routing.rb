#!/usr/bin/env ruby
# frozen_string_literal: true

# Topic Routing Example
# This example demonstrates wildcard pattern matching for topic-based routing

require_relative "../lib/messaging_system"
require "logger"

logger = Logger.new($stdout)
logger.level = Logger::INFO

broker = MessagingSystem::MessageBroker.new(logger: logger)

# Create subscribers with different patterns
all_orders = MessagingSystem::Subscriber.new("all-orders", broker: broker, async: true)
us_orders = MessagingSystem::Subscriber.new("us-orders", broker: broker, async: true)
eu_orders = MessagingSystem::Subscriber.new("eu-orders", broker: broker, async: true)
analytics = MessagingSystem::Subscriber.new("analytics", broker: broker, async: true)

# Subscribe with different patterns
all_orders.subscribe("orders.#") do |message|
  puts "[ALL] #{message.topic}: #{message.payload}"
end

us_orders.subscribe("orders.us.*") do |message|
  puts "[US] #{message.topic}: #{message.payload}"
end

eu_orders.subscribe("orders.eu.*") do |message|
  puts "[EU] #{message.topic}: #{message.payload}"
end

analytics.subscribe("*.*.completed") do |message|
  puts "[ANALYTICS] Completed event: #{message.topic}"
end

sleep 0.2

publisher = MessagingSystem::Publisher.new(broker: broker, name: "order-service")

puts "\n=== Publishing messages with different topics ===\n\n"

# These go to all-orders only
publisher.publish("orders.pending", { id: 1 })

# These go to all-orders and us-orders
publisher.publish("orders.us.created", { id: 2, region: "US" })
publisher.publish("orders.us.completed", { id: 3, region: "US" })

# These go to all-orders and eu-orders
publisher.publish("orders.eu.created", { id: 4, region: "EU" })
publisher.publish("orders.eu.completed", { id: 5, region: "EU" })

# This goes to all-orders and analytics (matches *.*.completed)
publisher.publish("orders.asia.completed", { id: 6, region: "ASIA" })

sleep 0.5

puts "\n=== Topic Matcher Examples ===\n"
matcher = broker.topic_matcher

patterns = {
  "orders.*" => ["orders.created", "orders.updated", "orders.deleted.v2"],
  "orders.#" => ["orders", "orders.created", "orders.us.created"],
  "*.orders.*" => ["us.orders.created", "eu.orders.updated"],
  "#.completed" => ["orders.completed", "orders.us.completed"],
}

patterns.each do |pattern, topics|
  puts "\nPattern: '#{pattern}'"
  topics.each do |topic|
    match = matcher.matches?(pattern, topic)
    puts "  #{topic}: #{match ? "✓ matches" : "✗ no match"}"
  end
end

broker.shutdown(timeout: 5)
puts "\nDone!"
