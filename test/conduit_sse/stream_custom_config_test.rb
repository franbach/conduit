# frozen_string_literal: true

require "test_helper"

class ConduitStreamCustomConfigTest < Minitest::Test
  def test_custom_chunk_normalizer
    events = []

    stream = ConduitSSE.new(
      parser: ->(p) { { data: p } },
      chunk_normalizer: lambda do |chunk|
        chunk.gsub("PREFIX:", "")
      end
    )

    stream.each { |e| events << e }
    stream << "PREFIX:data: hello\n\n"

    assert_equal [{ data: "hello" }], events
  end

  def test_custom_payload_start
    events = []

    stream = ConduitSSE.new(parser: ->(p) { { data: p } }, payload_start: "message:")

    stream.each { |e| events << e }
    stream << "message: hello\n\n"

    assert_equal [{ data: "hello" }], events
  end

  def test_custom_frame_separator
    events = []

    stream = ConduitSSE.new(parser: ->(p) { { data: p } }, frame_separator: "---")

    stream.each { |e| events << e }
    stream << "data: hello---data: world---"

    assert_equal [
      { data: "hello---" },
      { data: "world---" }
    ], events
  end

  def test_custom_ping_pattern
    pings = []

    stream = ConduitSSE.new(parser: ->(p) { { data: p } }, ping_pattern: "#")

    stream.on_ping { |p| pings << p }
    stream << "# ping\n\n"

    assert_equal 1, pings.length
    assert_equal "# ping", pings.first
  end

  def test_custom_sanitize_pattern
    # Test that custom sanitizer is applied
    sanitized_frames = []
    custom_sanitize = lambda { |frame|
      sanitized_frames << frame
      frame.strip
    }

    stream = ConduitSSE.new(parser: ->(p) { { data: p } }, sanitize_pattern: custom_sanitize)

    stream << "data: hello\n\n"

    assert_equal 1, sanitized_frames.length
    assert_equal "data: hello\n\n", sanitized_frames.first
  end

  def test_custom_payload_start_with_colon
    stream = ConduitSSE.new(parser: ->(p) { { data: p } }, payload_start: "event:")

    events = []
    stream.each { |e| events << e }
    stream << "event: custom\n\n"

    assert_equal [{ data: "custom" }], events
  end
end
