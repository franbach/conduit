require "test_helper"

class ConduitStreamPayloadTest < Minitest::Test
  def test_joins_multiple_data_lines
    events = []

    stream = Conduit.new(parser: ->(p) { { data: p } })

    stream.each { |e| events << e }
    stream << "data: hello\ndata: world\n\n"

    assert_equal [{ data: "hello\nworld" }], events
  end

  def test_ignores_non_data_lines
    events = []

    stream = Conduit.new(parser: ->(p) { { data: p } })

    stream.each { |e| events << e }
    stream << "event: message\ndata: hello\nid: 1\n\n"

    assert_equal [{ data: "hello" }], events
  end

  def test_ignores_frame_without_data
    events = []

    stream = Conduit.new(parser: ->(p) { { data: p } })

    stream.each { |e| events << e }
    stream << "event: test\n\n"

    assert_equal [], events
  end
end
