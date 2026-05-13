# frozen_string_literal: true

require "test_helper"

class ConduitStreamFuzzTest < Minitest::Test
  ITERATIONS = 100

  def test_random_chunk_splitting_produces_correct_events
    ITERATIONS.times do
      input = build_input_frames(%w[a b c d])
      chunks = random_chunks(input)

      events = []

      stream = ConduitSSE.new(parser: ->(p) { { data: p } })

      stream.on_parsed { |e| events << e }
      chunks.each { |chunk| stream << chunk }

      assert_equal expected_events(%w[a b c d]), events
    end
  end

  def test_random_chunk_splitting_with_multiline_data
    ITERATIONS.times do
      input = "data: hello\ndata: world\n\n"
      chunks = random_chunks(input)

      events = []

      stream = ConduitSSE.new(parser: ->(p) { { data: p } })

      stream.on_parsed { |e| events << e }
      chunks.each { |chunk| stream << chunk }

      assert_equal [{ data: "hello\nworld" }], events
    end
  end

  private

  def build_input_frames(values)
    values.map { |v| "data: #{v}\n\n" }.join
  end

  def expected_events(values)
    values.map { |v| { data: v } }
  end

  def random_chunks(string)
    chunks = []
    i = 0

    while i < string.length
      # random chunk size
      size = rand(1..5)
      chunks << string[i, size]
      i += size
    end

    chunks
  end
end
