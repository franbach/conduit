# frozen_string_literal: true

require_relative "conduit/version"
require_relative "conduit/stream"
require_relative "conduit/inspector"

# Conduit is a lightweight, zero-dependency Ruby gem for parsing Server-Sent Events (SSE) streams.
module Conduit
  def self.new(**)
    Stream.new(**)
  end
end
