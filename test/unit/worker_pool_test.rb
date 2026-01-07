# frozen_string_literal: true

require "test_helper"

module MessagingSystem
  class WorkerPoolTest < Minitest::Test
    def setup
      @logger = MockLogger.new
      @pool = WorkerPool.new(size: 3, name: "test", logger: @logger)
    end

    def teardown
      @pool.shutdown(timeout: 5) if @pool.running?
    end

    def test_start
      processed = Queue.new

      @pool.start { |task| processed << task }

      assert @pool.running?
      assert_equal 3, @pool.active_workers
    end

    def test_submit_task
      processed = Queue.new

      @pool.start { |task| processed << task }
      @pool.submit("task1")
      @pool.submit("task2")

      sleep 0.1

      assert_equal 2, processed.size
    end

    def test_submit_without_start_raises
      assert_raises(NotRunningError) do
        @pool.submit("task")
      end
    end

    def test_shutdown
      @pool.start { |_task| nil }
      @pool.shutdown(timeout: 5)

      refute @pool.running?
    end

    def test_graceful_shutdown_processes_pending
      processed = Queue.new

      @pool.start { |task| processed << task }

      10.times { |i| @pool.submit("task-#{i}") }
      @pool.shutdown(timeout: 5)

      assert_equal 10, processed.size
    end

    def test_stats
      @pool.start { |_task| nil }

      stats = @pool.stats

      assert_equal "test", stats[:name]
      assert_equal 3, stats[:size]
      assert stats[:running]
    end

    def test_task_processing_error_logged
      @pool.start { |_task| raise "test error" }
      @pool.submit("task")

      sleep 0.1

      error_logs = @logger.messages_at(:error)
      assert error_logs.any? { |l| l[:message].include?("error") }
    end

    def test_pending_tasks
      @pool.start { |_task| sleep 0.5 }

      10.times { |i| @pool.submit("task-#{i}") }

      assert @pool.pending_tasks.positive?
    end

    def test_submit_after_shutdown_raises
      @pool.start { |_task| nil }
      @pool.shutdown

      assert_raises(NotRunningError) do
        @pool.submit("task")
      end
    end

    def test_concurrent_task_processing
      results = Queue.new
      mutex = Mutex.new
      count = 0

      @pool.start do |task|
        mutex.synchronize { count += 1 }
        results << task
      end

      100.times { |i| @pool.submit("task-#{i}") }

      deadline = Time.now + 5
      sleep 0.01 until results.size >= 100 || Time.now > deadline

      @pool.shutdown(timeout: 5)

      assert_equal 100, results.size
    end
  end
end
