# frozen_string_literal: true

require "test_helper"
require "stringio"
require "conduit_sse/inspector"

class ConduitInspectorTest < Minitest::Test
  def setup
    @io = StringIO.new
    @stream = ConduitSSE.new(parser: ->(d) { d.upcase })
    @inspector = ConduitSSE::Inspector.attach(@stream, io: @io)
  end

  def test_does_not_clobber_user_callbacks
    received = []
    @stream.on_parsed { |p| received << p }

    @stream << "data: hi\n\n"

    assert_equal ["HI"], received
  end

  def test_counts_each_layer
    @stream << "data: a\n\n"
    @stream << ": ping\n\n"
    @stream << "data: b\nevent: greet\nid: 7\n\n"

    assert_equal 3, @inspector.counts[:chunk]
    assert_equal 2, @inspector.counts[:frame]
    assert_equal 2, @inspector.counts[:event]
    assert_equal 2, @inspector.counts[:parsed]
    assert_equal 1, @inspector.counts[:ping]
    # 1 + 3 fields (data, event, id) = 4
    assert_equal 4, @inspector.counts[:field]
  end

  def test_logs_event_metadata
    @stream << "event: greet\nid: 42\nretry: 1000\ndata: hi\n\n"

    output = @io.string
    assert_match(/\[EVENT #1\].*event="greet".*id="42".*retry=1000/, output)
    assert_match(/data: "hi"/, output)
  end

  def test_logs_errors_routed_through_on_error
    @stream.on_parsed { |_| raise "boom" }

    @stream << "data: x\n\n"

    assert_equal 1, @inspector.counts[:error]
    assert_match(/\[ERROR #1\] RuntimeError: boom/, @io.string)
  end

  def test_summary_includes_stream_state
    @stream << "id: 99\nretry: 3000\ndata: x\n\n"
    @inspector.summary

    output = @io.string
    assert_match(/\[SUMMARY\]/, output)
    assert_match(/last_event_id="99"/, output)
    assert_match(/retry_ms=3000/, output)
  end
end
