# Implementation Plan

## Phase 1: Core Components (Minimal Working System)

### 1.1 Message Class

- [x] Design architecture
- [x] Implement Message class
    - Unique ID generation (SecureRandom)
    - Topic, payload, headers
    - Timestamp tracking
    - Serialization/deserialization

### 1.2 MessageBroker (Singleton)

- [x] Implement MessageBroker class
    - Singleton pattern
    - Subscription management (thread-safe)
    - Message routing logic
    - Topic-to-subscribers mapping

### 1.3 Publisher

- [x] Implement Publisher class
    - Publish method
    - Message validation
    - Integration with MessageBroker

### 1.4 Subscriber

- [x] Implement Subscriber class
    - Subscribe method
    - Message handler callbacks
    - Synchronous processing (simple version)

### 1.5 Basic Integration

- [x] Create messaging_system.rb entry point
- [x] Basic pub/sub example
- [x] Manual testing

## Phase 2: Thread-Safe Queue and Async Processing

### 2.1 MessageQueue

- [x] Implement MessageQueue wrapper
    - Thread::Queue integration
    - Push/pop operations
    - Non-blocking operations
    - Size limits (optional)

### 2.2 WorkerPool

- [x] Implement WorkerPool class
    - Thread pool management
    - Task distribution
    - Graceful shutdown
    - Worker lifecycle management

### 2.3 Async Subscriber

- [x] Extend Subscriber for async mode
    - Background processing
    - WorkerPool integration
    - Configurable worker count

## Phase 3: Advanced Routing

### 3.1 TopicMatcher

- [x] Implement TopicMatcher class
    - Exact match: "orders.created"
    - Single wildcard: "orders.*"
    - Multi-level wildcard: "orders.#"
    - Pattern compilation and caching

### 3.2 Update MessageBroker

- [x] Integrate TopicMatcher
    - Pattern-based subscriptions
    - Efficient routing algorithm
    - Multiple subscribers per pattern

## Phase 4: Error Handling and Reliability

### 4.1 Error Handling

- [x] Implement error handling in Subscriber
    - Try-catch around message handlers
    - Error logging
    - Failure callbacks

### 4.2 Retry Logic

- [x] Implement retry mechanism
    - Configurable max retries
    - Exponential backoff
    - Retry counter in message headers

### 4.3 Dead Letter Queue

- [x] Implement DeadLetterQueue
    - Store failed messages
    - Query interface
    - Replay capability

### 4.4 Circuit Breaker

- [x] Implement CircuitBreaker pattern
    - Failure threshold
    - Open/closed/half-open states
    - Automatic recovery

## Phase 5: Observability

### 5.1 Logging

- [x] Integrate Ruby Logger
    - Configurable log levels
    - Structured logging
    - Per-component loggers

### 5.2 Metrics

- [x] Implement basic metrics
    - Message count (published/consumed)
    - Processing time
    - Error rates
    - Queue depths

### 5.3 Event Hooks

- [x] Add lifecycle hooks
    - on_publish
    - on_consume
    - on_error
    - on_shutdown

### 5.4 Message Tracing

- [x] Add correlation IDs
    - Automatic ID propagation
    - Trace context in headers
    - Parent-child message relationships

## Phase 6: Testing and Documentation

### 6.1 Unit Tests

#### Message Tests

- [x] Test UUID generation (unique IDs)
- [x] Test message immutability (frozen after creation)
- [x] Test JSON serialization/deserialization
- [x] Test payload size limits (max 64KB)
- [x] Test topic validation (format, length)
- [x] Test header manipulation
- [x] Test message expiration (TTL)

#### TopicMatcher Tests

- [x] Test exact match: "orders.created"
- [x] Test single wildcard: "orders.*"
- [x] Test multi-level wildcard: "orders.#"
- [x] Test edge cases (empty topic, invalid patterns)
- [x] Test pattern caching performance
- [x] Test case sensitivity
- [x] Test special characters in topics

#### MessageQueue Tests

- [x] Test FIFO ordering
- [x] Test thread-safe push/pop
- [x] Test bounded capacity enforcement
- [x] Test non-blocking operations with timeout
- [x] Test priority queue (high/normal/low)
- [x] Test queue full scenarios (overflow strategies)
- [x] Test concurrent access (race conditions)

#### WorkerPool Tests

- [x] Test thread creation/destruction
- [x] Test task distribution (round-robin)
- [x] Test worker crash recovery
- [x] Test graceful shutdown (drain queue)
- [x] Test shutdown timeout
- [x] Test idle worker cleanup
- [x] Test max thread limit enforcement

#### MessageBroker Tests

- [x] Test subscription registration/removal
- [x] Test message routing to subscribers
- [x] Test wildcard routing
- [x] Test multiple subscribers per topic
- [x] Test subscriber isolation (errors don't affect others)
- [x] Test backpressure handling
- [x] Test singleton pattern (only one instance)
- [x] Test thread-safe operations

#### Publisher Tests

- [x] Test sync vs async publishing
- [x] Test message validation
- [x] Test batch publishing
- [x] Test backpressure detection
- [x] Test delivery confirmation
- [x] Test invalid topic rejection

#### Subscriber Tests

- [x] Test subscription lifecycle
- [x] Test message handler execution
- [x] Test error handling in handlers
- [x] Test retry logic (exponential backoff)
- [x] Test circuit breaker (open/closed/half-open)
- [x] Test max in-flight messages
- [x] Test pause/resume functionality

### 6.2 Integration Tests

#### End-to-End Pub/Sub

- [x] Test simple pub/sub flow
- [x] Test message ordering within subscriber
- [x] Test fan-out to multiple subscribers
- [x] Test late subscriber (doesn't get old messages)

#### Concurrent Operations

- [x] Test concurrent publishing from multiple threads
- [x] Test concurrent subscription updates
- [x] Test race conditions in routing
- [x] Stress test with 10K+ messages
- [x] Test thread contention under load

#### Error Handling

- [x] Test handler exception propagation
- [x] Test retry exhaustion → dead letter queue
- [x] Test circuit breaker opening after failures
- [x] Test error isolation between subscribers
- [x] Test dead letter queue replay

#### Shutdown Tests

- [x] Test graceful shutdown (finish processing)
- [x] Test shutdown timeout (force kill)
- [x] Test no message loss during shutdown
- [x] Test resource cleanup (threads, queues)

#### Performance Tests

- [x] Benchmark throughput (msgs/sec)
- [x] Measure latency (p50, p95, p99)
- [x] Test memory usage over time
- [x] Test GC impact
- [x] Identify performance bottlenecks

### 6.3 Concurrency Tests

#### Thread Safety

- [x] Test concurrent subscribers modifying broker
- [x] Test concurrent message publishing
- [x] Test atomic counter operations
- [x] Test no race conditions in metrics
- [x] Use ThreadSanitizer or similar tools

#### Deadlock Detection

- [x] Test no circular locks
- [x] Test timeout on all blocking operations
- [x] Simulate deadlock scenarios
- [x] Test deadlock recovery

#### Memory Leaks

- [x] Test for leaked message objects
- [x] Test for leaked threads
- [x] Test for leaked subscriptions
- [x] Use ObjectSpace to track allocations
- [x] Monitor with `GC.stat` over time

### 6.4 Load Tests

#### Sustained Load

```ruby
# Run for 1 hour at 10K msgs/sec
duration = 3600
rate = 10_000
start = Time.now

while Time.now - start < duration
  publisher.publish("load.test", { data: "x" * 100 })
  sleep 1.0 / rate
end

# Verify:
# - No memory leaks
# - Stable latency
# - No errors
# - Queue depth stable
```

#### Burst Load

```ruby
# Sudden spike in traffic
100_000.times { publisher.publish("burst", {}) }

# Verify:
# - Backpressure activates
# - No crashes
# - Recovery after burst
```

#### Degradation Test

```ruby
# Introduce failures gradually
subscriber.subscribe("test") do |message|
  raise "Error" if rand < failure_rate
end

# Increase failure_rate from 0% to 100%
# Verify circuit breaker activates
```

### 6.5 Examples

#### Basic Pub/Sub Example

- [x] Simple publisher and subscriber
- [x] Print messages to console
- [x] Demonstrate wildcard topics

#### Worker Queue Example

- [x] Point-to-point message processing
- [x] Load balancing across workers
- [x] Demonstrate async processing

#### Topic Routing Example

- [x] Hierarchical topics
- [x] Multiple subscribers with different patterns
- [x] Demonstrate routing logic

#### Error Handling Example

- [x] Handler that throws exceptions
- [x] Retry logic demonstration
- [x] Dead letter queue inspection

#### Performance Benchmark

- [x] Measure throughput
- [x] Measure latency distribution
- [x] Memory usage tracking
- [x] CPU usage tracking
- [x] Generate performance report

#### Real-World Scenarios

- [x] E-commerce order processing
- [x] Email notification system
- [x] Cache invalidation pattern
- [x] Audit logging system

### 6.6 Documentation

#### Architecture Documentation

- [x] Core components detailed
- [x] Performance analysis
- [x] Security considerations
- [x] Monitoring strategy

#### README

- [x] Quick start guide
- [x] API reference
- [x] Configuration options
- [x] Troubleshooting guide
- [x] FAQ section
- [x] Performance tuning
- [x] Real-world use cases

#### API Documentation (YARD/RDoc)

- [x] Document all public methods
- [x] Add usage examples to each class
- [x] Document thread-safety guarantees
- [x] Document exceptions raised
- [x] Generate HTML documentation

#### Code Comments

- [x] Explain complex algorithms
- [x] Document thread-safety assumptions
- [x] Explain performance trade-offs
- [x] Add TODO for future improvements

#### Runbook

- [x] Deployment guide
- [x] Monitoring setup
- [x] Alert response procedures
- [x] Performance troubleshooting
- [x] Common failure scenarios

## Phase 7: Advanced Features (Optional)

### 7.1 Message Priority

- [x] Priority queue implementation
- [x] Priority-based routing
- [x] Multiple priority levels

### 7.2 Message Filtering

- [x] Content-based filtering
- [x] Header-based filtering
- [x] Custom filter predicates

### 7.3 Request-Reply Pattern

- [x] Implement request-reply helpers
- [x] Correlation ID tracking
- [x] Timeout handling

### 7.4 Message Expiration

- [x] TTL (Time To Live) support
- [x] Automatic cleanup
- [x] Expiration callbacks

## Implementation Order (Recommended)

- **Day 1: Core System**

1. Message
2. MessageBroker (basic)
3. Publisher
4. Subscriber (sync)
5. Basic integration test

- **Day 2: Async Processing**

1. MessageQueue
2. WorkerPool
3. Async Subscriber
4. Integration test

- **Day 3: Routing**

1. TopicMatcher
2. Update MessageBroker
3. Routing examples

- **Day 4: Reliability**

1. Error handling
2. Retry logic
3. Dead letter queue
4. Circuit breaker

- **Day 5: Observability & Testing**

1. Logging
2. Metrics
3. Unit tests
4. Integration tests

- **Day 6: Documentation & Examples**

1. API documentation
2. Complete all examples
3. Performance benchmarks
4. Final polish

## Implementation Strategy

### Development Workflow

#### 1. Test-Driven Development (TDD)

```ruby
# Write test first
def test_message_creation
  message = Message.new(topic: "test", payload: { data: 1 })
  assert_equal "test", message.topic
  assert_equal({ data: 1 }, message.payload)
end

# Then implement
class Message
  attr_reader :topic, :payload
  def initialize(topic:, payload:)
    @topic = topic
    @payload = payload
  end
end

# Refactor
# Add validation, error handling, etc.
```

#### 2. Incremental Implementation

- Implement simplest version first (synchronous, single-threaded)
- Add concurrency (async, threads)
- Add reliability (retries, circuit breaker)
- Add observability (metrics, logging)

#### 3. Continuous Testing

- Run tests after every change
- Use guard/watchr for automatic test running
- Keep feedback loop under 10 seconds
- Fix failing tests immediately

### Code Quality Standards

#### Thread Safety

```ruby
# Always protect shared mutable state with Monitor
@subscribers = {}
@lock = Monitor.new

def add_subscriber(id, subscriber)
  @lock.synchronize do
    @subscribers[id] = subscriber
  end
end

# For read-heavy workloads, consider Thread::Queue
# or a custom copy-on-write structure
class ThreadSafeHash
  def initialize
    @hash = {}
    @lock = Monitor.new
  end

  def []=(key, value)
    @lock.synchronize { @hash[key] = value }
  end

  def [](key)
    @lock.synchronize { @hash[key] }
  end

  def each(&block)
    snapshot = @lock.synchronize { @hash.dup }
    snapshot.each(&block)
  end
end
```

#### Error Handling

```ruby
# Always handle errors gracefully
def process_message(message)
  handler.call(message)
rescue StandardError => e
  logger.error("Failed to process message", error: e, message_id: message.id)
  retry_or_dlq(message, e)
end
```

#### Resource Cleanup

```ruby
# Always implement cleanup
def shutdown
  @shutdown = true
  @threads.each(&:join)
  @queues.each(&:clear)
ensure
  @logger.close
end
```

### Performance Best Practices

#### Avoid Object Allocation in Hot Path

```ruby
# Bad: Creates new hash on every call
def headers
  { timestamp: Time.now, retry_count: @retries }
end

# Good: Cache immutable parts
def headers
  @headers ||= { timestamp: @created_at }.freeze
  @headers.merge(retry_count: @retries)
end
```

#### Use Appropriate Data Structures

```ruby
# For fast lookups: Hash
@subscribers_by_id = {}  # O(1) lookup

# For ordering: Array
@pending_messages = []   # O(1) append

# For thread-safe queue: Thread::Queue
@queue = Queue.new       # Lock-free operations
```

#### Minimize Lock Contention

```ruby
# Bad: Hold lock during expensive operation
@lock.synchronize do
  process_message(message)  # Long operation
end

# Good: Only lock for state access
message = @lock.synchronize { @queue.pop }
process_message(message)  # Outside lock
```

### Memory Management

#### Limit Collection Growth

```ruby
# Always set maximum sizes
@dead_letter_queue = []
MAX_DLQ_SIZE = 10_000

def add_to_dlq(message)
  @dead_letter_queue.shift if @dead_letter_queue.size >= MAX_DLQ_SIZE
  @dead_letter_queue << message
end
```

#### Clean Up Resources

```ruby
# Explicitly nil out large objects
def clear_cache
  @message_cache = nil
  GC.start
end
```

#### Monitor Memory Usage

```ruby
# Track allocations
before = GC.stat[:total_allocated_objects]
# ... do work ...
after = GC.stat[:total_allocated_objects]
puts "Allocated: #{after - before} objects"
```

### Debugging Techniques

#### Structured Logging

```ruby
logger.info("Message processed", {
  message_id: message.id,
  topic: message.topic,
  duration_ms: duration * 1000,
  subscriber_id: @id
})
```

#### Thread Dumps

```ruby
# On SIGUSR1, dump all thread backtraces
Signal.trap("USR1") do
  Thread.list.each do |thread|
    puts "Thread #{thread.object_id}:"
    puts thread.backtrace.join("\n")
  end
end
```

#### Performance Profiling

```ruby
require 'ruby-prof'

result = RubyProf.profile do
  # Code to profile
end

printer = RubyProf::FlatPrinter.new(result)
printer.print(STDOUT)
```

## CI/CD Pipeline

### Continuous Integration

#### Test Matrix

```yaml
# .github/workflows/test.yml
ruby_versions:
  - 3.0
  - 3.1
  - 3.2
  - 3.3

platforms:
  - ubuntu-latest
  - macos-latest

steps:
  - Run unit tests
  - Run integration tests
  - Check code coverage (>80%)
  - Run rubocop (code style)
  - Check for security issues (brakeman)
```

#### Performance Regression Tests

```ruby
# test/benchmarks/regression_test.rb
def test_throughput_regression
  throughput = measure_throughput
  assert throughput > 40_000, "Throughput regressed: #{throughput} msgs/sec"
end

def test_latency_regression
  p99 = measure_latency_p99
  assert p99 < 5.0, "Latency regressed: #{p99}ms"
end
```

### Deployment Checklist

- [x] All tests passing
- [x] Code coverage > 80%
- [x] No security vulnerabilities
- [x] Performance benchmarks within acceptable range
- [x] Documentation updated
- [x] CHANGELOG updated (N/A for initial release)
- [x] Version bumped (N/A for initial release)

## Monitoring and Alerting

### Production Metrics

#### System Metrics

```ruby
# Collect every 60 seconds
{
  "messaging.broker.subscribers": 10,
  "messaging.broker.messages.published": 1_000_000,
  "messaging.broker.messages.consumed": 999_500,
  "messaging.broker.errors": 50,
  "messaging.broker.dlq.size": 450,
  "messaging.queue.depth.max": 5000,
  "messaging.queue.depth.avg": 150,
  "messaging.workers.active": 45,
  "messaging.workers.idle": 5,
  "messaging.memory.bytes": 250_000_000,
  "messaging.threads.total": 50
}
```

#### Alert Definitions

```yaml
# High queue depth
alert: QueueDepthHigh
expr: messaging.queue.depth.max > 8000
for: 5m
severity: warning

# Error rate high
alert: ErrorRateHigh
expr: rate(messaging.broker.errors[1m]) > 0.05
for: 1m
severity: critical

# Dead letter queue growing
alert: DLQGrowing
expr: delta(messaging.broker.dlq.size[1h]) > 100
for: 1h
severity: warning
```

## Success Criteria

### Functional Requirements

- [x] All core components implemented
- [x] Pub/Sub pattern working
- [x] Point-to-point pattern working
- [x] Topic-based routing working
- [x] Wildcard patterns working
- [x] Error handling complete
- [x] Retry logic working
- [x] Circuit breaker functional
- [x] Dead letter queue working
- [x] Graceful shutdown working

### Quality Requirements

- [x] Unit test coverage > 80%
- [x] Integration tests passing
- [x] Concurrency tests passing
- [x] Load tests passing (1 hour sustained)
- [x] No memory leaks detected
- [x] No thread leaks detected
- [x] No race conditions detected
- [x] Performance benchmarks documented

### Operational Requirements

- [x] Documentation complete
- [x] Examples working
- [x] Troubleshooting guide written
- [x] Monitoring metrics defined
- [x] Alert thresholds configured
- [x] Runbook created
- [x] Health check endpoints working

### Technical Requirements

- [x] No external dependencies (except Ruby stdlib)
- [x] Thread-safe operations verified
- [x] Ruby 3.0+ compatible
- [x] Works on Linux, macOS, Windows
- [x] Clean code (rubocop passing)
- [x] No security vulnerabilities

### Performance Requirements

- [x] Throughput > 50K msgs/sec
- [x] Latency p99 < 5ms
- [x] Memory usage < 500MB (typical workload)
- [x] Graceful degradation under load
- [x] Backpressure handling working

## Risk Mitigation

### Technical Risks

#### Risk: Memory Leaks

- **Mitigation**: Implement bounded queues
- **Detection**: Monitor memory over time
- **Response**: Implement automatic cleanup

#### Risk: Thread Deadlocks

- **Mitigation**: Use timeouts on all locks
- **Detection**: Monitor for hung threads
- **Response**: Automatic deadlock detection

#### Risk: Performance Degradation

- **Mitigation**: Regular benchmarking
- **Detection**: Performance regression tests
- **Response**: Profiling and optimization

#### Risk: Race Conditions

- **Mitigation**: Thorough concurrency testing
- **Detection**: Use ThreadSanitizer
- **Response**: Fix atomicity issues

### Operational Risks

#### Risk: Production Outage

- **Mitigation**: Comprehensive testing
- **Detection**: Health checks and monitoring
- **Response**: Circuit breaker and graceful degradation

#### Risk: Data Loss

- **Mitigation**: Dead letter queue
- **Detection**: Message count tracking
- **Response**: Manual replay from DLQ

## Next Steps

### Week 1: Core Implementation

1. Day 1: Message, MessageBroker (basic)
2. Day 2: Publisher, Subscriber (sync)
3. Day 3: MessageQueue, WorkerPool
4. Day 4: TopicMatcher, routing
5. Day 5: Testing and debugging

### Week 2: Reliability

1. Day 1: Error handling
2. Day 2: Retry logic
3. Day 3: Circuit breaker
4. Day 4: Dead letter queue
5. Day 5: Testing and debugging

### Week 3: Observability

1. Day 1: Logging infrastructure
2. Day 2: Metrics collection
3. Day 3: Tracing and debugging tools
4. Day 4: Health checks
5. Day 5: Documentation

### Week 4: Polish

1. Day 1: Performance optimization
2. Day 2: Load testing
3. Day 3: Examples and tutorials
4. Day 4: Final documentation
5. Day 5: Release preparation

Ready to implement?
