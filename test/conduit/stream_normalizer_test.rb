require "test_helper"

class ConduitStreamNormalizerTest < Minitest::Test
  def test_uses_custom_chunk_normalizer
    events = []

    stream = Conduit.new(
      parser: ->(p) { { data: p } },
      chunk_normalizer: ->(chunk) {
        chunk.gsub("PREFIX:", "")
      }
    )

    stream.each { |e| events << e }
    stream << "PREFIX:data: hello\n\n"

    assert_equal [{ data: "hello" }], events
  end

  def test_default_normalizer_handles_crlf
    events = []

    stream = Conduit.new(parser: ->(p) { { data: p } })

    stream.each { |e| events << e }
    stream << "data: hello\r\n\r\n"

    assert_equal [{ data: "hello" }], events
  end
end
