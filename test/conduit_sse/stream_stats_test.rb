# frozen_string_literal: true

require "test_helper"

class ConduitStreamStatsTest < Minitest::Test
  def test_stats_disabled_by_default_returns_nil
    stream = ConduitSSE.new(parser: ->(d) { d })

    assert_nil stream.stats

    stream << "data: hello\n\n"

    # Still nil after processing; no bookkeeping happens.
    assert_nil stream.stats
  end

  def test_stats_disabled_does_not_count_errors
    stream = ConduitSSE.new(parser: ->(d) { d })
    errors = []
    stream.on_error { |e| errors << e }
    stream.on_parsed { raise "boom" }

    stream << "data: test\n\n"

    assert_nil stream.stats
    assert_equal 1, errors.length
  end

  def test_buffer_size_works_without_stats
    stream = ConduitSSE.new(parser: ->(d) { d })

    assert_equal 0, stream.buffer_size

    stream << "data: hello"
    assert stream.buffer_size.positive?

    stream << "\n\n"
    assert_equal 0, stream.buffer_size
  end

  def test_buffer_size_returns_current_buffer_size
    stream = ConduitSSE.new(parser: ->(d) { d }, stats: true)

    assert_equal 0, stream.buffer_size

    stream << "data: hello"
    assert stream.buffer_size.positive?

    stream << "\n\n"
    assert_equal 0, stream.buffer_size
  end

  def test_stats_returns_counts
    stream = ConduitSSE.new(parser: ->(d) { d }, stats: true)

    assert_equal({ avg_fields_per_frame: 0 }, stream.stats)

    stream << "data: hello\n\n"

    stats = stream.stats
    assert_equal 1, stats[:chunk]
    assert_equal 1, stats[:frame]
    assert_equal 1, stats[:event]
    assert_equal 1, stats[:parsed]
    assert_equal 1, stats[:field] # data field
    assert_equal 0, stats[:ping]
    assert_equal 0, stats[:error]
    assert_equal 1.0, stats[:avg_fields_per_frame]
  end

  def test_stats_increments_on_multiple_events
    stream = ConduitSSE.new(parser: ->(d) { d }, stats: true)

    stream << "data: first\n\n"
    stream << "data: second\n\n"

    stats = stream.stats
    assert_equal 2, stats[:chunk]
    assert_equal 2, stats[:frame]
    assert_equal 2, stats[:event]
    assert_equal 2, stats[:parsed]
    assert_equal 1.0, stats[:avg_fields_per_frame]
  end

  def test_stats_tracks_pings
    stream = ConduitSSE.new(parser: ->(d) { d }, stats: true)

    stream << ": ping\n\n"

    stats = stream.stats
    assert_equal 1, stats[:chunk]
    assert_equal 1, stats[:ping]
    assert_equal 0, stats[:event]
  end

  def test_stats_tracks_errors
    stream = ConduitSSE.new(parser: ->(d) { d }, stats: true)

    errors = []
    stream.on_error { |e| errors << e }

    stream.on_parsed { raise "boom" }
    stream << "data: test\n\n"

    stats = stream.stats
    assert_equal 1, stats[:error]
    assert_equal 1, errors.length
  end

  def test_stats_returns_copy_not_internal_hash
    stream = ConduitSSE.new(parser: ->(d) { d }, stats: true)

    stats1 = stream.stats
    stream << "data: test\n\n"
    stats2 = stream.stats

    refute_equal stats1, stats2
    assert_equal 0, stats1[:chunk]
    assert_equal 1, stats2[:chunk]
  end

  def test_stats_tracks_multiple_fields
    stream = ConduitSSE.new(parser: ->(d) { d }, stats: true)

    stream << "data: hello\nevent: message\nid: 123\n\n"

    stats = stream.stats
    assert_equal 3, stats[:field] # data, event, id
    assert_equal 3.0, stats[:avg_fields_per_frame]
  end

  def test_custom_frame_separator
    stream = ConduitSSE.new(parser: ->(d) { d }, frame_separator: "---", stats: true)

    stream << "data: hello---"

    stats = stream.stats
    assert_equal 1, stats[:frame]
    assert_equal 1, stats[:event]
  end
end
