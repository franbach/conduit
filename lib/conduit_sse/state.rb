# frozen_string_literal: true

require_relative "callbacks"

module ConduitSSE
  # Runtime, per-stream mutable state.
  #
  # Where {Config} answers *what to do* (parser, separators, patterns), `State`
  # answers *where we are*: how much data is buffered, the last event id/retry
  # seen, accumulated counters when stats are enabled, etc.
  #
  # Mutated continuously while the stream is processing data; lives for the
  # lifetime of one {Stream} instance.
  class State
    # SSE spec state — last id and retry values observed on the wire. Mutated
    # as `id:` / `retry:` fields are parsed.
    attr_accessor :last_event_id, :retry_ms, :last_event_type

    # The raw input buffer. Mutated via `<<`, `index`, `slice!`.
    # @return [String]
    attr_reader :buffer

    # Registered user callbacks for every pipeline stage.
    # @return [Callbacks]
    attr_reader :callbacks

    def initialize(stats_enabled:)
      @buffer          = +""
      @callbacks       = Callbacks.new
      @last_event_id   = nil
      @retry_ms        = nil
      @last_event_type = nil
      @stats           = stats_enabled ? Hash.new(0) : nil
      @total_fields    = stats_enabled ? 0 : nil
    end

    # Current buffer size in bytes.
    # @return [Integer]
    def buffer_size
      @buffer.bytesize
    end

    # Whether per-stage counter tracking is active for this stream.
    # @return [Boolean]
    def stats_enabled?
      !@stats.nil?
    end

    # Increment one stats counter by 1. No-op when stats are disabled.
    def increment_stat(key)
      @stats[key] += 1 if @stats
    end

    # Accumulate parsed fields into the rolling total used to compute
    # `:avg_fields_per_frame`. No-op when stats are disabled.
    def add_fields(count)
      @total_fields += count if @stats
    end

    # Snapshot of the counters plus the derived `:avg_fields_per_frame`.
    # Returns `nil` when stats tracking is disabled, so callers can branch on
    # the return value without a separate `#stats_enabled?` check.
    #
    # @return [Hash{Symbol => Integer, Float}, nil]
    def stats_snapshot
      return nil unless @stats

      snapshot = @stats.dup
      snapshot[:avg_fields_per_frame] = avg_fields_per_frame
      snapshot
    end

    private

    def avg_fields_per_frame
      return 0 unless @stats[:frame].positive?

      (@total_fields.to_f / @stats[:frame]).round(2)
    end
  end
end
