# frozen_string_literal: true

require "test_helper"

class ConduitStreamChunkingTest < Minitest::Test
  def test_handles_split_chunks
    events = []

    stream = ConduitSSE.new(parser: ->(p) { { data: p } })

    stream.each { |e| events << e }

    stream << "data: hel"
    stream << "lo\n\n"

    assert_equal [{ data: "hello" }], events
  end

  def test_handles_multiple_splits
    events = []

    stream = ConduitSSE.new(parser: ->(p) { { data: p } })

    stream.each { |e| events << e }

    stream << "data:"
    stream << " he"
    stream << "llo\n"
    stream << "\n"

    assert_equal [{ data: "hello" }], events
  end

  def test_handles_chunk_with_multiple_frames_and_partial_tail
    events = []

    stream = ConduitSSE.new(parser: ->(p) { { data: p } })

    stream.each { |e| events << e }

    stream << "data: a\n\ndata: b\n\ndata: c"
    stream << "\n\n"

    assert_equal [
      { data: "a" },
      { data: "b" },
      { data: "c" }
    ], events
  end
end
