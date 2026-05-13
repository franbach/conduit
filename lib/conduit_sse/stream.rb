# frozen_string_literal: true

require_relative "callbacks"
require_relative "config"
require_relative "defaults"
require_relative "event"
require_relative "state"

module ConduitSSE
  # Core streaming parser for Server-Sent Events (SSE).
  #
  # See {ConduitSSE::Config} for the full list of configuration knobs and
  # the two equivalent constructor forms (kwargs and block).
  class Stream
    # The frozen, validated configuration for this stream.
    # @return [ConduitSSE::Config]
    attr_reader :config

    # The runtime mutable state (buffer, last_event_id, retry_ms, counters).
    # @return [ConduitSSE::State]
    attr_reader :state

    # @yieldparam config [ConduitSSE::Config] Mutable configuration object;
    #   any values set in the block win over the kwargs.
    def initialize(**opts, &block)
      @config = Config.new(**opts)
      block&.call(@config)
      @config.finalize!
      @state = State.new(stats_enabled: @config.stats)
    end

    # @return [String, nil] The last `id:` value seen on the wire.
    def last_event_id = @state.last_event_id

    # @return [Integer, String, nil] The last `retry:` value seen on the wire.
    def retry_ms = @state.retry_ms

    # Current buffer size in bytes.
    #
    # Returns the size of the internal buffer, useful for monitoring memory usage
    # during long-running streams.
    #
    # @return [Integer] Buffer size in bytes
    def buffer_size
      @state.buffer_size
    end

    # Stream statistics.
    #
    # Returns a hash with counts of all processed items, useful for monitoring
    # and debugging without the overhead of the Inspector's logging.
    #
    # Stats are **opt-in**: pass `stats: true` to {#initialize} to enable
    # tracking. When stats are disabled (the default), this method returns nil
    # and the parser does zero stats bookkeeping per event.
    #
    # @return [Hash, nil] Statistics hash with keys: :chunk, :frame, :event,
    #   :parsed, :ping, :field, :error, :avg_fields_per_frame; or nil when
    #   stats tracking is disabled.
    def stats
      @state.stats_snapshot
    end

    # Raw chunk as it arrived (after normalization).
    #
    # The chunk is a string that has been normalized (UTF-8 encoded, CRLF→LF).
    # This is called for every chunk fed to the stream via <<, regardless of
    # whether the chunk contains complete frames or partial data.
    #
    # @yield [chunk] The normalized chunk string
    def on_chunk(&block)
      @state.callbacks.on(:chunk, &block)
    end

    # Complete frame text (after sanitization), regardless of whether it produces an event.
    #
    # A frame is the text between frame separators (default: "\n\n").
    # This callback receives the raw frame string after sanitization (default: strip).
    # This includes frames that may not produce events (e.g., frames without data fields).
    # Ping frames are handled separately by on_ping and do not trigger this callback.
    #
    # @yield [frame] The sanitized frame string
    def on_frame(&block)
      @state.callbacks.on(:frame, &block)
    end

    # Fully parsed SSE event as a {ConduitSSE::Event}.
    #
    # This callback receives a ConduitSSE::Event object with the following attributes:
    # - event: Event type (defaults to "message")
    # - data: Joined data field content (data lines joined by "\n")
    # - id: Last event ID from the SSE spec
    # - retry: Retry delay in milliseconds from the SSE spec
    #
    # Only called for frames that contain at least one data field.
    # Use this callback when you need access to SSE metadata (event type, id, retry).
    #
    # @param type [String, Array<String>, nil] Optional event type(s) to filter by.
    #   If provided, the callback only triggers for matching event types.
    # @yield [event] A ConduitSSE::Event object
    def on_event(type: nil, &block)
      if type
        wrapped_block = proc do |event|
          filter_match = Array(type).include?(event.event)
          next unless filter_match

          block.call(event)
        end
        @state.callbacks.on(:event, &wrapped_block)
      else
        @state.callbacks.on(:event, &block)
      end
    end

    # Result of running the configured parser over an event's data.
    #
    # The parser receives ONLY the data field content (joined by "\n"), not the entire frame.
    # If you need access to other SSE fields (event type, id, retry), use on_event instead.
    #
    # If the parser raises an error and an on_error handler is registered,
    # the error is routed to on_error and this callback is NOT invoked for that event.
    #
    # @param type [String, Array<String>, nil] Optional event type(s) to filter by.
    #   If provided, the callback only triggers for matching event types.
    # @yield [parsed] Whatever your parser lambda returns
    def on_parsed(type: nil, &block)
      if type
        wrapped_block = proc do |parsed|
          # We need access to the event type here, but on_parsed receives parsed data
          # We need to track the last event type to filter properly
          filter_match = Array(type).include?(@state.last_event_type || "message")
          next unless filter_match

          block.call(parsed)
        end
        @state.callbacks.on(:parsed, &wrapped_block)
      else
        @state.callbacks.on(:parsed, &block)
      end
    end

    # Ping/comment frame.
    #
    # Ping frames are identified by the ping_pattern (default: ":").
    # These are typically used for keep-alive messages or comments.
    # Ping frames do NOT trigger on_frame or on_event callbacks.
    #
    # @yield [frame] The ping frame string
    def on_ping(&block)
      @state.callbacks.on(:ping, &block)
    end

    # Every parsed SSE field line. Yields (name, value) for every field, including
    # the standard ones (data/event/id/retry) and any custom fields a server emits.
    #
    # Per the SSE spec, fields are parsed one per line with the format "name: value".
    # This callback is invoked for each field line as it's parsed from the frame.
    #
    # @yield [name, value] The field name and value as strings
    def on_field(&block)
      @state.callbacks.on(:field, &block)
    end

    # Errors raised by any callback or by the parser.
    #
    # When a callback (other than on_error itself) or the parser raises an error,
    # it's routed to this handler if registered. This prevents errors from interrupting
    # the stream processing.
    #
    # If on_error is not registered, errors will bubble up and interrupt processing.
    # If on_error itself raises, that error will bubble up.
    #
    # @yield [error] The exception that was raised
    def on_error(&block)
      wrapped_block = proc do |error|
        @state.increment_stat(:error)
        block.call(error)
      end
      @state.callbacks.on(:error, &wrapped_block)
    end

    # Feed a chunk of data to the stream for processing.
    #
    # Chunks are typically received from an HTTP stream (e.g., Net::HTTP response body).
    # The chunk is normalized, buffered, and then processed for complete frames.
    # Returns self for method chaining.
    #
    # @param chunk [String] Raw data chunk from the stream
    # @return [self]
    def <<(chunk)
      chunk = normalize_chunk(chunk)

      @state.callbacks.emit(:chunk, chunk)
      @state.buffer << chunk
      @state.increment_stat(:chunk)

      process_frames
      self
    end

    # Signal end-of-input. Processes any bytes left in the buffer as a final frame,
    # so trailing data not terminated by the frame separator still produces an event.
    #
    # Call this when the underlying transport closes cleanly without a trailing "\n\n"
    # (typical for many HTTP SSE servers). Safe to call multiple times; safe to call on
    # an empty buffer; safe to keep using the stream afterwards.
    #
    # @return [self]
    def finish
      buffer = @state.buffer
      return self if buffer.empty?

      remainder = buffer.slice!(0, buffer.length)
      process_frame(remainder)
      self
    end
    alias close finish

    # Enumerable interface for iterating over parsed events.
    #
    # Provides a convenient way to iterate over the results of your parser.
    # Without a block, returns an Enumerator. With a block, registers an on_parsed
    # callback and returns self for chaining.
    #
    # @yield [parsed] The result of your parser
    # @return [Enumerator, self]
    def each(&block)
      return enum_for(:each) unless block

      on_parsed(&block)
      self
    end

    private

    # Process buffered chunks to extract complete frames.
    #
    # Scans the buffer for the frame separator and extracts complete frames.
    # Incomplete frames remain in the buffer for the next chunk.
    # This is called automatically after each chunk is fed via <<.
    def process_frames
      buffer    = @state.buffer
      separator = @config.frame_separator

      loop do
        idx = buffer.index(separator)
        break unless idx

        frame = buffer.slice!(0, idx + separator.length)
        process_frame(frame)
      end
    end

    # Process a single frame through the parsing pipeline.
    #
    # Processing stages:
    # 1. Sanitize the frame (default: strip whitespace)
    # 2. Check if it's a ping frame (if so, emit on_ping and return)
    # 3. Emit on_frame with the sanitized frame
    # 4. Parse SSE fields from the frame
    # 5. Emit on_field for each field line
    # 6. Track SSE state (id, retry) from standard fields
    # 7. If data fields present, build Event object and emit on_event
    # 8. Apply user parser to the data content
    # 9. Emit on_parsed with the parser result
    #
    # @param frame [String] The raw frame string
    def process_frame(frame)
      frame = sanitize(frame)
      return if frame.empty?

      callbacks = @state.callbacks
      @state.increment_stat(:frame)

      if ping?(frame)
        callbacks.emit(:ping, frame)
        @state.increment_stat(:ping)
        return
      end

      callbacks.emit(:frame, frame)

      type = nil
      data_lines = []
      frame_fields = 0
      data_field = @config.data_field

      parse_fields(frame).each do |name, value|
        callbacks.emit(:field, name, value)
        @state.increment_stat(:field)
        frame_fields += 1

        case name
        when data_field  then data_lines << value
        when "event"     then type = value
        when "id"        then @state.last_event_id = value unless value.include?("\u0000")
        when "retry"     then @state.retry_ms = lenient_int(value)
        end
      end

      @state.add_fields(frame_fields)
      return if data_lines.empty?

      data = data_lines.join("\n")
      @state.last_event_type = type || "message"

      event = Event.new(
        event: @state.last_event_type,
        data: data,
        id: @state.last_event_id,
        retry: @state.retry_ms
      )

      callbacks.emit(:event, event)
      @state.increment_stat(:event)

      parsed = callbacks.call_safely(@config.parser, data)
      return if parsed.equal?(Callbacks::FAILED)

      callbacks.emit(:parsed, parsed)
      @state.increment_stat(:parsed)
    end

    # Per https://html.spec.whatwg.org/multipage/server-sent-events.html, parse one field per line:
    #   - empty line: skipped
    #   - line with no ":" : whole line is the field name, value is ""
    #   - otherwise: field name = before first ":", value = after, with one optional leading space stripped
    #   - empty field name (line starting with ":") is a comment and ignored
    def parse_fields(frame)
      frame.lines.filter_map do |line|
        line = line.chomp
        next if line.empty?

        idx = line.index(":")
        if idx.nil?
          [line, ""]
        else
          name = line[0...idx]
          next if name.empty?

          value = line[(idx + 1)..] || ""
          value = value[1..] if value.start_with?(" ")
          [name, value]
        end
      end
    end

    def lenient_int(value)
      Integer(value, 10)
    rescue ArgumentError, TypeError
      value
    end

    def normalize_chunk(chunk)
      @config.chunk_normalizer.call(chunk)
    end

    def sanitize(frame)
      @config.sanitize_pattern.call(frame)
    end

    def ping?(frame)
      frame.start_with?(@config.ping_pattern)
    end
  end
end
