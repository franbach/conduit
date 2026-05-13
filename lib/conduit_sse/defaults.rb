# frozen_string_literal: true

module ConduitSSE
  # Default configurations for ConduitSSE::Stream
  module Defaults
    PING_PATTERN    = ":"
    FRAME_SEPARATOR = "\n\n"
    PAYLOAD_START   = "data:"

    module_function

    def to_utf8(string)
      string.dup
            .force_encoding("UTF-8")
            .encode("UTF-8", invalid: :replace, undef: :replace)
            .gsub("\r\n", "\n")
    end

    SANITIZE_PATTERN  = ->(frame) { to_utf8(frame).strip }
    CHUNK_NORMALIZER  = ->(chunk) { to_utf8(chunk) }
  end
end
