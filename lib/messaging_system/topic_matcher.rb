# frozen_string_literal: true

module MessagingSystem
  class TopicMatcher
    SINGLE_WILDCARD = "*"
    MULTI_WILDCARD = "#"
    SEPARATOR = "."

    def initialize
      @pattern_cache = {}
      @lock = Mutex.new
    end

    def matches?(pattern, topic)
      return true if pattern == topic
      return true if pattern == MULTI_WILDCARD

      pattern_segments = get_cached_segments(pattern)
      topic_segments = topic.split(SEPARATOR)

      match_segments(pattern_segments, topic_segments, 0, 0)
    end

    def valid_pattern?(pattern)
      return false if pattern.nil? || pattern.empty?
      return false if pattern.include?("..")
      return false if pattern.start_with?(SEPARATOR) || pattern.end_with?(SEPARATOR)

      segments = pattern.split(SEPARATOR)
      segments.all? { |seg| valid_segment?(seg) }
    end

    def valid_topic?(topic)
      return false if topic.nil? || topic.empty?
      return false if topic.include?(SINGLE_WILDCARD) || topic.include?(MULTI_WILDCARD)

      valid_pattern?(topic)
    end

    def clear_cache
      @lock.synchronize { @pattern_cache.clear }
    end

    def cache_size
      @lock.synchronize { @pattern_cache.size }
    end

    private

    def get_cached_segments(pattern)
      @lock.synchronize do
        @pattern_cache[pattern] ||= pattern.split(SEPARATOR)
      end
    end

    def match_segments(pattern_segs, topic_segs, p_idx, t_idx)
      # Both exhausted - match
      return true if p_idx >= pattern_segs.length && t_idx >= topic_segs.length

      # Pattern exhausted but topic remains - no match
      return false if p_idx >= pattern_segs.length

      current = pattern_segs[p_idx]

      case current
      when MULTI_WILDCARD
        # # can match zero or more segments
        # Try matching zero segments (skip #)
        return true if match_segments(pattern_segs, topic_segs, p_idx + 1, t_idx)

        # Try matching one or more segments
        (t_idx...topic_segs.length).each do |i|
          return true if match_segments(pattern_segs, topic_segs, p_idx + 1, i + 1)
        end

        # # matches all remaining segments
        p_idx + 1 >= pattern_segs.length
      when SINGLE_WILDCARD
        # * must match exactly one segment
        return false if t_idx >= topic_segs.length

        match_segments(pattern_segs, topic_segs, p_idx + 1, t_idx + 1)
      else
        # Literal match
        return false if t_idx >= topic_segs.length
        return false unless current == topic_segs[t_idx]

        match_segments(pattern_segs, topic_segs, p_idx + 1, t_idx + 1)
      end
    end

    def valid_segment?(segment)
      return true if segment == SINGLE_WILDCARD
      return true if segment == MULTI_WILDCARD

      segment.match?(/\A[a-zA-Z0-9_-]+\z/)
    end
  end
end
