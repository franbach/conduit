# frozen_string_literal: true

require "test_helper"

class ConduitStreamNormalizerTest < Minitest::Test
  def test_default_normalizer_handles_crlf
    events = []

    stream = ConduitSSE.new(parser: ->(p) { { data: p } })

    stream.each { |e| events << e }
    stream << "data: hello\r\n\r\n"

    assert_equal [{ data: "hello" }], events
  end
end
