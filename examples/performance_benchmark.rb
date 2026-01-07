#!/usr/bin/env ruby
# frozen_string_literal: true

# Performance Benchmark Example
# This example measures throughput and latency of the messaging system

require_relative "../lib/messaging_system"
require "benchmark"

puts "Ruby Messaging System - Performance Benchmark"
puts "=" * 50

# Configuration
MESSAGE_COUNT = 10_000
WORKER_COUNT = 10
PAYLOAD_SIZE = 100

broker = MessagingSystem::MessageBroker.new

# Tracking
received_count = 0
latencies = []
mutex = Mutex.new
start_times = {}

subscriber = MessagingSystem::Subscriber.new(
  "benchmark-worker",
  broker: broker,
  async: true,
  worker_count: WORKER_COUNT,
  queue_size: MESSAGE_COUNT,
)

subscriber.subscribe("benchmark.test") do |message|
  receive_time = Time.now
  send_time = message.payload[:sent_at]

  mutex.synchronize do
    received_count += 1
    latencies << (receive_time.to_f - send_time) * 1000 # ms
  end
end

sleep 0.2

publisher = MessagingSystem::Publisher.new(broker: broker, name: "benchmark")

puts "\nTest Configuration:"
puts "  Messages: #{MESSAGE_COUNT}"
puts "  Workers: #{WORKER_COUNT}"
puts "  Payload size: #{PAYLOAD_SIZE} bytes"

# Warm up
puts "\nWarming up..."
100.times do
  publisher.publish("benchmark.test", { sent_at: Time.now.to_f, data: "x" * PAYLOAD_SIZE })
end
sleep 0.5
received_count = 0
latencies.clear

# Benchmark publishing
puts "\nRunning benchmark..."
publish_time = Benchmark.realtime do
  MESSAGE_COUNT.times do
    publisher.publish("benchmark.test", {
                        sent_at: Time.now.to_f,
                        data: "x" * PAYLOAD_SIZE,
                      })
  end
end

# Wait for all messages to be processed
deadline = Time.now + 30
sleep 0.1 until received_count >= MESSAGE_COUNT || Time.now > deadline

total_time = Time.now - (Time.now - publish_time)

# Calculate statistics
puts "\n#{"=" * 50}"
puts "Results"
puts "=" * 50

puts "\nThroughput:"
publish_rate = MESSAGE_COUNT / publish_time
puts "  Publish rate: #{publish_rate.round(0)} msgs/sec"
puts "  Publish time: #{(publish_time * 1000).round(2)} ms"

if latencies.any?
  sorted = latencies.sort
  p50 = sorted[sorted.size * 50 / 100]
  p95 = sorted[sorted.size * 95 / 100]
  p99 = sorted[sorted.size * 99 / 100]
  avg = latencies.sum / latencies.size

  puts "\nLatency:"
  puts "  Average: #{avg.round(3)} ms"
  puts "  p50: #{p50.round(3)} ms"
  puts "  p95: #{p95.round(3)} ms"
  puts "  p99: #{p99.round(3)} ms"
  puts "  Min: #{sorted.first.round(3)} ms"
  puts "  Max: #{sorted.last.round(3)} ms"
end

puts "\nProcessing:"
puts "  Messages sent: #{MESSAGE_COUNT}"
puts "  Messages received: #{received_count}"
puts "  Success rate: #{(received_count.to_f / MESSAGE_COUNT * 100).round(2)}%"

# Memory stats
puts "\nMemory:"
puts "  Process memory: #{(`ps -o rss= -p #{Process.pid}`.to_i / 1024.0).round(2)} MB"

# GC stats
gc_stats = GC.stat
puts "\nGC Stats:"
puts "  Total allocations: #{gc_stats[:total_allocated_objects]}"
puts "  GC count: #{gc_stats[:count]}"

broker.shutdown(timeout: 10)

puts "\nBenchmark complete!"
