# frozen_string_literal: true

require "test_helper"

class ConduitStreamSseFieldsTest < Minitest::Test
  def make_stream
    ConduitSSE.new(parser: ->(d) { d })
  end

  # on_event fires with ConduitSSE::Event

  def test_on_event_emits_full_event_with_defaults
    events = []
    stream = make_stream

    stream.on_event { |e| events << e }
    stream << "data: hello\n\n"

    assert_equal 1, events.size
    assert_kind_of ConduitSSE::Event, events.first
    assert_equal "hello",   events.first.data
    assert_equal "message", events.first.event
    assert_nil events.first.id
    assert_nil events.first.retry
  end

  def test_event_field_sets_type
    events = []
    stream = make_stream

    stream.on_event { |e| events << e }
    stream << "event: ping\ndata: x\n\n"

    assert_equal "ping", events.first.event
  end

  def test_id_field_sets_last_event_id_and_propagates
    events = []
    stream = make_stream

    stream.on_event { |e| events << e }
    stream << "id: 1\ndata: a\n\n"
    stream << "data: b\n\n" # no id, should inherit

    assert_equal "1", events[0].id
    assert_equal "1", events[1].id
    assert_equal "1", stream.last_event_id
  end

  def test_id_with_null_byte_is_ignored
    stream = make_stream
    stream << "id: bad\u0000id\ndata: x\n\n"

    assert_nil stream.last_event_id
  end

  def test_empty_id_clears_to_empty_string
    stream = make_stream
    stream << "id: 1\ndata: a\n\n"

    assert_equal "1", stream.last_event_id

    stream << "id:\ndata: b\n\n"

    assert_equal "", stream.last_event_id
  end

  def test_retry_field_sets_retry_ms_as_integer
    stream = make_stream
    stream << "retry: 5000\ndata: x\n\n"

    assert_equal 5000, stream.retry_ms
  end

  def test_retry_lenient_falls_back_to_raw_string_for_non_integer
    stream = make_stream
    stream << "retry: soon\ndata: x\n\n"

    assert_equal "soon", stream.retry_ms
  end

  def test_last_wins_for_multiple_event_id_retry_in_one_frame
    events = []
    stream = make_stream

    stream.on_event { |e| events << e }
    stream << "event: a\nevent: b\nid: 1\nid: 2\nretry: 100\nretry: 200\ndata: x\n\n"

    assert_equal "b", events.first.event
    assert_equal "2", events.first.id
    assert_equal 200, events.first.retry
  end

  def test_data_lines_concatenated_with_newline
    events = []
    stream = make_stream

    stream.on_event { |e| events << e }
    stream << "data: hello\ndata: world\n\n"

    assert_equal "hello\nworld", events.first.data
  end

  def test_frame_with_no_data_does_not_emit_event
    events = []
    parsed = []
    stream = make_stream

    stream.on_event  { |e| events << e }
    stream.on_parsed { |p| parsed << p }
    stream << "event: ping\nid: 1\n\n"

    assert_empty events
    assert_empty parsed
    # but stream state was still updated
    assert_equal "1", stream.last_event_id
  end

  # on_field fires for every parsed field

  def test_on_field_fires_for_every_field_including_standard_ones
    seen = []
    stream = make_stream

    stream.on_field { |name, value| seen << [name, value] }
    stream << "data: hi\nevent: foo\nid: 1\nretry: 100\ncustom: yes\nx-trace: abc\n\n"

    assert_equal [
      %w[data hi],
      %w[event foo],
      %w[id 1],
      %w[retry 100],
      %w[custom yes],
      %w[x-trace abc]
    ], seen
  end

  def test_on_field_not_invoked_for_comment_lines
    seen = []
    stream = make_stream

    stream.on_field { |name, value| seen << [name, value] }
    stream << "data: hi\n: this is a comment\n\n"

    assert_equal [%w[data hi]], seen
  end

  # Ordering: on_event before parser before on_parsed

  def test_callbacks_fire_in_layered_order
    order = []
    stream = ConduitSSE.new(parser: lambda { |d|
      order << :parser
      d.upcase
    })

    stream.on_frame  { |_| order << :frame }
    stream.on_event  { |_| order << :event }
    stream.on_parsed { |_| order << :parsed }
    stream << "data: x\n\n"

    assert_equal %i[frame event parser parsed], order
  end

  # Parser still receives the joined data string

  def test_parser_receives_data_string
    received = nil
    stream = ConduitSSE.new(parser: lambda { |d|
      received = d
      d
    })
    stream << "event: foo\nid: 1\ndata: hello\ndata: world\n\n"

    assert_equal "hello\nworld", received
  end
end
