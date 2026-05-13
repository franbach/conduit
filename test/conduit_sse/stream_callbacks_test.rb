# frozen_string_literal: true

require "test_helper"

class ConduitStreamCallbacksTest < Minitest::Test
  def test_on_chunk_is_called
    chunks = []

    stream = ConduitSSE.new(parser: ->(p) { { data: p } })

    stream.on_chunk { |c| chunks << c }

    ["data: a\n\n", "data: b\n\n"].each do |chunk|
      stream << chunk
    end

    assert_equal ["data: a\n\n", "data: b\n\n"], chunks
  end

  def test_on_frame_is_called
    frames = []

    stream = ConduitSSE.new(parser: ->(p) { { data: p } })

    stream.on_frame { |f| frames << f }
    stream << "data: hello\n\n"

    assert_equal 1, frames.size
  end

  def test_on_parsed_is_called
    events = []

    stream = ConduitSSE.new(parser: ->(p) { { data: p } })

    stream.on_parsed { |e| events << e }
    stream << "data: hello\n\n"

    assert_equal 1, events.size
  end
end
