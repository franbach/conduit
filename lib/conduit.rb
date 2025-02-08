# frozen_string_literal: true

require_relative "conduit/version"
require_relative "conduit/stream"
require_relative "conduit/inspector"

module Conduit
  def self.new(**)
    Stream.new(**)
  end
end
