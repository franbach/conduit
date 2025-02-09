require "test_helper"

class ConduitStreamBasicTest < Minitest::Test
  def test_parses_simple_frame
    events = []

    stream = Conduit.new(parser: ->(p) { { data: p } })

    stream.each { |e| events << e }
    stream << "data: hello\n\n"

    assert_equal [{ data: "hello" }], events
  end

  def test_ignores_empty_frames
    events = []

    stream = Conduit.new(parser: ->(p) { { data: p } })

    stream.each { |e| events << e }
    stream << "\n\n"

    assert_equal [], events
  end

  def test_handles_multiple_frames_in_single_chunk
    events = []

    stream = Conduit.new(parser: ->(p) { { data: p } })

    stream.each { |e| events << e }
    stream << "data: a\n\ndata: b\n\n"

    assert_equal [
      { data: "a" },
      { data: "b" }
    ], events
  end
end
