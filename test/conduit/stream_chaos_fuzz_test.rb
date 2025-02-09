require "test_helper"

class ConduitStreamChaosFuzzTest < Minitest::Test
  ITERATIONS = 100

  def test_randomized_stream_with_noise_and_crlf
    ITERATIONS.times do
      input = build_chaos_stream
      chunks = random_chunks(input)

      events = []

      stream = Conduit.new(parser: ->(p) { { data: p } })

      stream.each { |e| events << e }
      chunks.each { |c| stream << c }

      assert_equal extract_expected(input), events
    end
  end

  private

  def build_chaos_stream
    parts = []

    rand(5..12).times do
      case rand(4)
      when 0
        parts << valid_frame(random_word)
      when 1
        parts << multiline_frame(random_word, random_word)
      when 2
        parts << ping_frame
      when 3
        parts << noise
      end
    end

    parts.join
  end

  def valid_frame(value)
    "data: #{value}\n\n"
  end

  def multiline_frame(a, b)
    "data: #{a}\ndata: #{b}\n\n"
  end

  def ping_frame
    ": ping\n\n"
  end

  def noise
    ["\n", "\r\n", "   ", "\t"].sample
  end

  def random_chunks(string)
    chunks = []
    i = 0

    while i < string.length
      size = rand(1..8)
      chunks << string[i, size]
      i += size
    end

    chunks
  end

  def extract_expected(input)
    normalized = input.gsub("\r\n", "\n")

    frames = normalized.split("\n\n")

    frames.filter_map do |frame|
      next if frame.strip.empty?
      next if frame.strip.start_with?(":")

      data_lines = frame.lines
                        .map(&:strip)
                        .select { |l| l.start_with?("data:") }
                        .map { |l| l.sub("data:", "").strip }

      next if data_lines.empty?

      { data: data_lines.join("\n") }
    end
  end

  def random_word
    ("a".."z").to_a.sample(rand(3..8)).join
  end
end
