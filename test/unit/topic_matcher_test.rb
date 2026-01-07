# frozen_string_literal: true

require "test_helper"

module MessagingSystem
  class TopicMatcherTest < Minitest::Test
    def setup
      @matcher = TopicMatcher.new
    end

    def test_exact_match
      assert @matcher.matches?("orders.created", "orders.created")
      refute @matcher.matches?("orders.created", "orders.updated")
    end

    def test_single_wildcard_matches_one_segment
      assert @matcher.matches?("orders.*", "orders.created")
      assert @matcher.matches?("orders.*", "orders.updated")
      refute @matcher.matches?("orders.*", "orders.created.v2")
      refute @matcher.matches?("orders.*", "orders")
    end

    def test_multi_wildcard_matches_zero_or_more_segments
      assert @matcher.matches?("orders.#", "orders")
      assert @matcher.matches?("orders.#", "orders.created")
      assert @matcher.matches?("orders.#", "orders.created.v2")
      assert @matcher.matches?("orders.#", "orders.created.v2.final")
    end

    def test_multi_wildcard_alone_matches_everything
      assert @matcher.matches?("#", "anything")
      assert @matcher.matches?("#", "anything.goes.here")
    end

    def test_wildcard_in_middle
      assert @matcher.matches?("orders.*.completed", "orders.123.completed")
      refute @matcher.matches?("orders.*.completed", "orders.123.456.completed")
    end

    def test_multi_wildcard_in_middle
      assert @matcher.matches?("orders.#.completed", "orders.completed")
      assert @matcher.matches?("orders.#.completed", "orders.123.completed")
      assert @matcher.matches?("orders.#.completed", "orders.123.456.completed")
    end

    def test_combined_wildcards
      assert @matcher.matches?("*.orders.#", "us.orders")
      assert @matcher.matches?("*.orders.#", "us.orders.created")
      assert @matcher.matches?("*.orders.#", "eu.orders.created.v2")
    end

    def test_case_sensitive_matching
      refute @matcher.matches?("orders.created", "ORDERS.CREATED")
      refute @matcher.matches?("Orders.Created", "orders.created")
    end

    def test_valid_pattern
      assert @matcher.valid_pattern?("orders")
      assert @matcher.valid_pattern?("orders.created")
      assert @matcher.valid_pattern?("orders.*")
      assert @matcher.valid_pattern?("orders.#")
      assert @matcher.valid_pattern?("orders-v2")
      assert @matcher.valid_pattern?("orders_v2")
    end

    def test_invalid_pattern
      refute @matcher.valid_pattern?(nil)
      refute @matcher.valid_pattern?("")
      refute @matcher.valid_pattern?(".orders")
      refute @matcher.valid_pattern?("orders.")
      refute @matcher.valid_pattern?("orders..created")
    end

    def test_valid_topic
      assert @matcher.valid_topic?("orders")
      assert @matcher.valid_topic?("orders.created")
      assert @matcher.valid_topic?("orders-v2")
    end

    def test_invalid_topic_with_wildcards
      refute @matcher.valid_topic?("orders.*")
      refute @matcher.valid_topic?("orders.#")
    end

    def test_pattern_caching
      pattern = "orders.*"

      @matcher.matches?(pattern, "orders.created")
      @matcher.matches?(pattern, "orders.updated")

      assert_equal 1, @matcher.cache_size
    end

    def test_clear_cache
      @matcher.matches?("orders.*", "orders.created")
      @matcher.matches?("users.*", "users.created")

      assert_equal 2, @matcher.cache_size

      @matcher.clear_cache

      assert_equal 0, @matcher.cache_size
    end

    def test_special_characters_in_segments
      assert @matcher.matches?("orders-v2.created", "orders-v2.created")
      assert @matcher.matches?("orders_v2.created", "orders_v2.created")
    end

    def test_numeric_segments
      assert @matcher.matches?("orders.123", "orders.123")
      assert @matcher.matches?("orders.*", "orders.123")
    end

    def test_empty_result_for_no_match
      refute @matcher.matches?("orders.created", "users.created")
      refute @matcher.matches?("orders.*", "users.created")
    end
  end
end
