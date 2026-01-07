#!/usr/bin/env ruby
# frozen_string_literal: true

# Worker Queue Example
# This example demonstrates point-to-point messaging with worker pool

require_relative "../lib/messaging_system"
require "logger"

logger = Logger.new($stdout)
logger.level = Logger::INFO

broker = MessagingSystem::MessageBroker.new(logger: logger)

# Track which worker processed each task
processed = Queue.new
worker_counts = Hash.new(0)
mutex = Mutex.new

# Create a subscriber with multiple workers (simulating a work queue)
worker = MessagingSystem::Subscriber.new(
  "task-worker",
  broker: broker,
  logger: logger,
  async: true,
  worker_count: 4, # 4 concurrent workers
  queue_size: 100,
)

worker.subscribe("tasks.process") do |message|
  thread_name = Thread.current.name || Thread.current.object_id.to_s
  task_id = message.payload[:task_id]

  # Simulate work
  sleep(rand(0.05..0.15))

  mutex.synchronize do
    worker_counts[thread_name] += 1
  end

  processed << { task_id: task_id, worker: thread_name }
  puts "[Worker #{thread_name}] Processed task #{task_id}"
end

sleep 0.2

publisher = MessagingSystem::Publisher.new(broker: broker, name: "task-producer")

puts "\n=== Submitting 20 tasks ===\n\n"

# Submit multiple tasks
20.times do |i|
  publisher.publish("tasks.process", {
                      task_id: i + 1,
                      data: "Task data #{i + 1}",
                      submitted_at: Time.now.iso8601,
                    })
end

# Wait for processing
puts "\n=== Waiting for processing ===\n"
deadline = Time.now + 5
sleep 0.1 until processed.size >= 20 || Time.now > deadline

# Collect results
results = []
results << processed.pop until processed.empty?

puts "\n=== Results ===\n"
puts "Total tasks processed: #{results.size}"

puts "\nWork distribution across workers:"
worker_counts.each do |worker, count|
  puts "  #{worker}: #{count} tasks"
end

puts "\n=== Worker Pool Stats ===\n"
stats = worker.stats
puts "Processed count: #{stats[:processed_count]}"
puts "Error count: #{stats[:error_count]}"
puts "Pending messages: #{stats[:pending_messages]}"

puts "Active workers: #{stats[:worker_pool][:active_workers]}" if stats[:worker_pool]

broker.shutdown(timeout: 5)
puts "\nDone!"
