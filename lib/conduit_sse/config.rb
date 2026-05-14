# frozen_string_literal: true

require_relative "defaults"

module ConduitSSE
  # Mutable configuration for {ConduitSSE::Stream}.
  #
  # `Config` is the canonical bag of knobs the stream reads from at
  # construction time. It loads its own defaults, exposes plain accessors so a
  # block can mutate it freely, and validates its invariants on demand.
  #
  # Two ways to fill it in (both supported by `Stream#initialize`):
  #
  #   # Keyword form
  #   ConduitSSE.new(parser: ->(d) { JSON.parse(d) }, stats: true)
  #
  #   # Block form
  #   ConduitSSE.new do |config|
  #     config.parser           = ->(d) { JSON.parse(d) }
  #     config.stats            = true
  #     config.frame_separator  = "\r\n\r\n"
  #   end
  #
  # The two can be mixed; kwargs seed the config and the block then mutates
  # whatever it likes on top.
  #
  # @!attribute [rw] parser
  #   @return [#call] Required. Callable that receives the joined data field
  #     content of one SSE event and returns whatever shape the application
  #     wants (e.g. `JSON.parse`, a domain object, the raw string).
  # @!attribute [rw] chunk_normalizer
  #   @return [#call] Transforms incoming chunks before processing
  #     (default: UTF-8 normalize + CRLF→LF).
  # @!attribute [rw] frame_separator
  #   @return [String] Delimiter between frames (default: `"\n\n"`).
  # @!attribute [rw] payload_start
  #   @return [String] Prefix that identifies the data field; the trailing
  #     `":"` is stripped to derive the field name (default: `"data:"`).
  # @!attribute [rw] ping_pattern
  #   @return [String] Pattern identifying ping/comment frames
  #     (default: `":"`).
  # @!attribute [rw] sanitize_pattern
  #   @return [#call] Cleans or validates frame content
  #     (default: UTF-8 normalize + strip).
  # @!attribute [rw] stats
  #   @return [Boolean] When true, the stream maintains a per-stage counter
  #     hash exposed via {Stream#stats}. Disabled by default to avoid any
  #     per-event overhead on hot paths.
  class Config
    SETTABLE_KEYS = %i[
      parser
      chunk_normalizer
      frame_separator
      payload_start
      ping_pattern
      sanitize_pattern
      stats
    ].freeze

    attr_accessor(*SETTABLE_KEYS)

    def initialize(**opts)
      validate_keys!(opts)

      @parser           = opts[:parser]
      @chunk_normalizer = opts[:chunk_normalizer] || Defaults::CHUNK_NORMALIZER
      @sanitize_pattern = opts[:sanitize_pattern] || Defaults::SANITIZE_PATTERN
      @frame_separator  = opts[:frame_separator]  || Defaults::FRAME_SEPARATOR
      @payload_start    = opts[:payload_start]    || Defaults::PAYLOAD_START
      @ping_pattern     = opts[:ping_pattern]     || Defaults::PING_PATTERN
      @stats            = opts.fetch(:stats, false)
    end

    # Enforce the one hard invariant: a usable parser must be present.
    # Called by the stream after the configuration block (if any) has run, so
    # callers can supply the parser via either kwarg or block.
    #
    # @raise [ArgumentError] if {#parser} doesn't respond to `:call`.
    def validate!
      return if @parser.respond_to?(:call)

      raise ArgumentError, "parser must be a Proc (respond to #call)"
    end

    # Lock the configuration in: validate, compute derived values, and freeze.
    # After this returns, the Config is immutable and every accessor (including
    # {#data_field}) is safe to read on a hot path.
    #
    # @return [self]
    def finalize!
      validate!
      @data_field = @payload_start.chomp(":")
      freeze
      self
    end

    # The SSE field name derived from {#payload_start} (the trailing ":" is
    # stripped). Computed once by {#finalize!}.
    #
    # @return [String] e.g. `"data"` for the default `payload_start` of `"data:"`.
    attr_reader :data_field

    private

    def validate_keys!(opts)
      unknown = opts.keys - SETTABLE_KEYS
      return if unknown.empty?

      raise ArgumentError, "unknown configuration keys: #{unknown.join(", ")}"
    end
  end
end
