require "test_helper"

class ConduitDefaultsTest < Minitest::Test
  # Protocol constants

  def test_protocol_constants
    assert_equal ":",     Conduit::Defaults::PING_PATTERN
    assert_equal "\n\n",  Conduit::Defaults::FRAME_SEPARATOR
    assert_equal "data:", Conduit::Defaults::PAYLOAD_START
  end

  # to_utf8

  def test_to_utf8_passes_valid_utf8_through
    assert_equal "hello", Conduit::Defaults.to_utf8("hello")
  end

  def test_to_utf8_normalizes_crlf_to_lf
    assert_equal "a\nb\nc", Conduit::Defaults.to_utf8("a\r\nb\r\nc")
  end

  def test_to_utf8_replaces_invalid_bytes_instead_of_raising
    invalid = "abc\xFFdef".dup.force_encoding("UTF-8")

    result = Conduit::Defaults.to_utf8(invalid)

    assert_equal Encoding::UTF_8, result.encoding
    assert result.valid_encoding?
    assert_match(/abc.*def/, result)
  end

  def test_to_utf8_does_not_mutate_input
    input = "hello\r\n".dup
    Conduit::Defaults.to_utf8(input)

    assert_equal "hello\r\n", input
  end

  # SANITIZE_PATTERN vs CHUNK_NORMALIZER

  def test_sanitize_pattern_strips_surrounding_whitespace
    assert_equal "data: x", Conduit::Defaults::SANITIZE_PATTERN.call("  data: x  \n")
  end

  def test_chunk_normalizer_does_not_strip
    # Chunks may legitimately end mid-frame; whitespace at edges is significant.
    assert_equal "  data: x  \n", Conduit::Defaults::CHUNK_NORMALIZER.call("  data: x  \r\n")
  end

  def test_chunk_normalizer_normalizes_crlf
    assert_equal "data: a\ndata: b\n\n", Conduit::Defaults::CHUNK_NORMALIZER.call("data: a\r\ndata: b\r\n\r\n")
  end
end
