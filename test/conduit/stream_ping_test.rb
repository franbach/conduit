require "test_helper"

class ConduitStreamPingTest < Minitest::Test
  def test_detects_ping_frame
    pings = []

    stream = Conduit.new(parser: ->(p) { { data: p } })

    stream.on_ping { |p| pings << p }
    stream << ": ping\n\n"

    assert_equal 1, pings.size
  end

  def test_ping_does_not_emit_event
    events = []

    stream = Conduit.new(parser: ->(p) { { data: p } })

    stream.each { |e| events << e }
    stream << ": ping\n\n"

    assert_equal [], events
  end
end
