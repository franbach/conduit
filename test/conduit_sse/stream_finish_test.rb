# frozen_string_literal: true

require "test_helper"

class ConduitStreamFinishTest < Minitest::Test
  def make_stream
    ConduitSSE.new(parser: ->(d) { d })
  end

  def test_finish_flushes_a_trailing_unterminated_frame
    parsed = []
    stream = make_stream
    stream.on_parsed { |p| parsed << p }

    stream << "data: hello" # no trailing "\n\n"
    assert_empty parsed, "must not emit before finish"

    stream.finish

    assert_equal ["hello"], parsed
  end

  def test_finish_emits_full_event_object_for_trailing_frame
    events = []
    stream = make_stream
    stream.on_event { |e| events << e }

    stream << "event: greet\nid: 7\ndata: hi"
    stream.finish

    assert_equal 1, events.size
    assert_equal "greet", events.first.event
    assert_equal "7",     events.first.id
    assert_equal "hi",    events.first.data
  end

  def test_finish_on_empty_buffer_is_noop
    parsed = []
    stream = make_stream
    stream.on_parsed { |p| parsed << p }

    stream.finish # never fed anything
    stream << "data: a\n\n"
    stream.finish # buffer already drained by separator

    assert_equal ["a"], parsed
  end

  def test_finish_is_idempotent
    parsed = []
    stream = make_stream
    stream.on_parsed { |p| parsed << p }

    stream << "data: tail"
    stream.finish
    stream.finish
    stream.finish

    assert_equal ["tail"], parsed
  end

  def test_stream_remains_usable_after_finish
    parsed = []
    stream = make_stream
    stream.on_parsed { |p| parsed << p }

    stream << "data: first"
    stream.finish

    stream << "data: second\n\n"

    assert_equal %w[first second], parsed
  end

  def test_finish_returns_self_for_chaining
    stream = make_stream
    assert_same stream, stream.finish
  end

  def test_finish_with_only_whitespace_emits_nothing
    parsed = []
    stream = make_stream
    stream.on_parsed { |p| parsed << p }

    stream << "\n"
    stream.finish

    assert_empty parsed
  end

  def test_close_alias_works
    parsed = []
    stream = make_stream
    stream.on_parsed { |p| parsed << p }

    stream << "data: bye"
    stream.close

    assert_equal ["bye"], parsed
  end
end
