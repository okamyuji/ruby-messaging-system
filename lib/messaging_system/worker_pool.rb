# frozen_string_literal: true

require "monitor"

module MessagingSystem
  class WorkerPool
    attr_reader :size
    attr_reader :name

    def initialize(size:, name: "worker", logger: nil)
      @size = size
      @name = name
      @logger = logger || NullLogger.new
      @workers = []
      @task_queue = Queue.new
      @lock = Monitor.new
      @running = false
      @shutdown_requested = false
      @processed_count = 0
      @error_count = 0
    end

    def start(&task_handler)
      @lock.synchronize do
        return if @running

        @running = true
        @shutdown_requested = false
        @task_handler = task_handler

        @size.times do |i|
          worker = create_worker(i)
          @workers << worker
        end
      end

      @logger.info("WorkerPool '#{@name}' started with #{@size} workers")
      self
    end

    def submit(task)
      raise NotRunningError, "Worker pool is not running" unless @running
      raise ShutdownError, "Worker pool is shutting down" if @shutdown_requested

      @task_queue << task
      true
    end

    def shutdown(timeout: 30)
      @lock.synchronize do
        return unless @running

        @shutdown_requested = true
        @running = false
      end

      @logger.info("WorkerPool '#{@name}' shutdown initiated")

      @size.times { @task_queue << :shutdown }

      deadline = Time.now + timeout
      @workers.each do |worker|
        remaining = deadline - Time.now
        break if remaining <= 0

        worker.join(remaining)
      end

      force_shutdown if any_workers_alive?

      @lock.synchronize do
        @workers.clear
        @task_queue.clear
      end

      @logger.info("WorkerPool '#{@name}' shutdown complete")
      true
    end

    def running?
      @running
    end

    def pending_tasks
      @task_queue.size
    end

    def active_workers
      @workers.count(&:alive?)
    end

    def stats
      @lock.synchronize do
        {
          name: @name,
          size: @size,
          running: @running,
          active_workers: active_workers,
          pending_tasks: pending_tasks,
          processed_count: @processed_count,
          error_count: @error_count,
        }
      end
    end

    private

    def create_worker(index)
      Thread.new do
        Thread.current.name = "#{@name}-#{index}"
        worker_loop
      end
    end

    def worker_loop
      loop do
        task = @task_queue.pop
        break if task == :shutdown

        process_task(task)
      end
    rescue StandardError => e
      @logger.error("Worker crashed: #{e.message}")
      @lock.synchronize { @error_count += 1 }
    end

    def process_task(task)
      @task_handler&.call(task)
      @lock.synchronize { @processed_count += 1 }
    rescue StandardError => e
      @lock.synchronize { @error_count += 1 }
      @logger.error("Task processing error: #{e.message}")
      raise
    end

    def any_workers_alive?
      @workers.any?(&:alive?)
    end

    def force_shutdown
      @logger.warn("Force killing remaining workers")
      @workers.each { |w| w.kill if w.alive? }
    end
  end
end
