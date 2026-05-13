# frozen_string_literal: true

require "test_helper"

class ConduitStateTest < Minitest::Test
  def test_buffer_starts_empty_and_is_mutable
    state = ConduitSSE::State.new(stats_enabled: false)

    assert_equal 0, state.buffer_size

    state.buffer << "abc"
    assert_equal 3, state.buffer_size
  end

  def test_stats_disabled_returns_nil_snapshot_and_noop_mutations
    state = ConduitSSE::State.new(stats_enabled: false)

    refute_predicate state, :stats_enabled?
    assert_nil state.stats_snapshot

    # These must be safe no-ops when stats are off.
    state.increment_stat(:chunk)
    state.add_fields(5)

    assert_nil state.stats_snapshot
  end

  def test_stats_enabled_accumulates_counters
    state = ConduitSSE::State.new(stats_enabled: true)

    assert_predicate state, :stats_enabled?

    state.increment_stat(:chunk)
    state.increment_stat(:frame)
    state.increment_stat(:frame)
    state.add_fields(4)

    snapshot = state.stats_snapshot
    assert_equal 1,   snapshot[:chunk]
    assert_equal 2,   snapshot[:frame]
    assert_equal 2.0, snapshot[:avg_fields_per_frame]
  end

  def test_avg_fields_per_frame_is_zero_when_no_frames_yet
    state = ConduitSSE::State.new(stats_enabled: true)
    state.increment_stat(:chunk) # frames still zero

    assert_equal 0, state.stats_snapshot[:avg_fields_per_frame]
  end

  def test_snapshot_is_a_copy
    state = ConduitSSE::State.new(stats_enabled: true)
    state.increment_stat(:chunk)

    first = state.stats_snapshot
    state.increment_stat(:chunk)
    second = state.stats_snapshot

    assert_equal 1, first[:chunk]
    assert_equal 2, second[:chunk]
  end

  def test_sse_state_accessors_are_writable
    state = ConduitSSE::State.new(stats_enabled: false)
    state.last_event_id   = "42"
    state.retry_ms        = 2000
    state.last_event_type = "delta"

    assert_equal "42",    state.last_event_id
    assert_equal 2000,    state.retry_ms
    assert_equal "delta", state.last_event_type
  end
end
