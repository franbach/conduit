# frozen_string_literal: true

require_relative "conduit_sse/version"
require_relative "conduit_sse/stream"
require_relative "conduit_sse/inspector"

# ConduitSSE is a lightweight, zero-dependency Ruby gem for parsing Server-Sent Events (SSE) streams.
module ConduitSSE
  def self.new(**, &)
    Stream.new(**, &)
  end
end
