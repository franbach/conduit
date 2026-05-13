# frozen_string_literal: true

require "test_helper"

class ConduitStreamFilterTest < Minitest::Test
  def test_on_event_filter_by_single_type
    events = []

    stream = ConduitSSE.new(parser: ->(d) { d })
    stream.on_event(type: "message") { |e| events << e }

    stream << "event: message\ndata: hello\n\n"
    stream << "event: other\ndata: world\n\n"

    assert_equal 1, events.length
    assert_equal "message", events.first.event
    assert_equal "hello", events.first.data
  end

  def test_on_event_filter_by_multiple_types
    events = []

    stream = ConduitSSE.new(parser: ->(d) { d })
    stream.on_event(type: %w[message update]) { |e| events << e }

    stream << "event: message\ndata: hello\n\n"
    stream << "event: update\ndata: world\n\n"
    stream << "event: other\ndata: test\n\n"

    assert_equal 2, events.length
    assert_equal "message", events[0].event
    assert_equal "update", events[1].event
  end

  def test_on_event_without_filter_receives_all
    events = []

    stream = ConduitSSE.new(parser: ->(d) { d })
    stream.on_event { |e| events << e }

    stream << "event: message\ndata: hello\n\n"
    stream << "event: other\ndata: world\n\n"

    assert_equal 2, events.length
  end

  def test_on_event_filter_default_message_type
    events = []

    stream = ConduitSSE.new(parser: ->(d) { d })
    stream.on_event(type: "message") { |e| events << e }

    # Events without explicit type default to "message"
    stream << "data: hello\n\n"

    assert_equal 1, events.length
    assert_equal "message", events.first.event
  end

  def test_on_parsed_filter_by_single_type
    parsed_items = []

    stream = ConduitSSE.new(parser: ->(d) { d })
    stream.on_parsed(type: "message") { |p| parsed_items << p }

    stream << "event: message\ndata: hello\n\n"
    stream << "event: other\ndata: world\n\n"

    assert_equal 1, parsed_items.length
    assert_equal "hello", parsed_items.first
  end

  def test_on_parsed_filter_by_multiple_types
    parsed_items = []

    stream = ConduitSSE.new(parser: ->(d) { d })
    stream.on_parsed(type: %w[message update]) { |p| parsed_items << p }

    stream << "event: message\ndata: hello\n\n"
    stream << "event: update\ndata: world\n\n"
    stream << "event: other\ndata: test\n\n"

    assert_equal 2, parsed_items.length
    assert_equal "hello", parsed_items[0]
    assert_equal "world", parsed_items[1]
  end

  def test_on_parsed_without_filter_receives_all
    parsed_items = []

    stream = ConduitSSE.new(parser: ->(d) { d })
    stream.on_parsed { |p| parsed_items << p }

    stream << "event: message\ndata: hello\n\n"
    stream << "event: other\ndata: world\n\n"

    assert_equal 2, parsed_items.length
  end

  def test_multiple_callbacks_with_different_filters
    message_events = []
    update_events = []

    stream = ConduitSSE.new(parser: ->(d) { d })
    stream.on_event(type: "message") { |e| message_events << e }
    stream.on_event(type: "update") { |e| update_events << e }

    stream << "event: message\ndata: hello\n\n"
    stream << "event: update\ndata: world\n\n"

    assert_equal 1, message_events.length
    assert_equal "message", message_events.first.event
    assert_equal 1, update_events.length
    assert_equal "update", update_events.first.event
  end

  def test_filter_does_not_affect_frame_callback
    frames = []

    stream = ConduitSSE.new(parser: ->(d) { d })
    stream.on_event(type: "message") { |e| } # Filtered callback
    stream.on_frame { |f| frames << f }

    stream << "event: message\ndata: hello\n\n"
    stream << "event: other\ndata: world\n\n"

    # Frame callback should still receive all frames
    assert_equal 2, frames.length
  end
end
