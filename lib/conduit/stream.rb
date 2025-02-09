# frozen_string_literal: true

require_relative "callbacks"
require_relative "defaults"
require_relative "event"

module Conduit
  class Stream
    # Initialize a new Stream with optional customizations.
    #
    # @param parser [Proc] Required. Callable that receives the joined data string of an SSE event and returns whatever shape the application wants.
    # @param chunk_normalizer [Proc] Optional. Transforms incoming chunks before processing.
    # @param frame_separator [String] Optional. Delimiter that separates frames in the stream.
    # @param payload_start [String] Optional. Prefix used to identify the data field (the trailing ":" is stripped to derive the field name).
    # @param ping_pattern [String] Optional. Pattern identifying ping frames.
    # @param sanitize_pattern [Proc] Optional. Cleans or validates frame content.
    def initialize(
      parser:,
      chunk_normalizer: nil,
      frame_separator: nil,
      payload_start: nil,
      ping_pattern: nil,
      sanitize_pattern: nil
    )
      raise ArgumentError, "parser must be a Proc (respond to #call)" unless parser.respond_to?(:call)

      @parser           = parser
      @chunk_normalizer = chunk_normalizer || Defaults::CHUNK_NORMALIZER
      @sanitize_pattern = sanitize_pattern || Defaults::SANITIZE_PATTERN
      @frame_separator  = frame_separator  || Defaults::FRAME_SEPARATOR
      @payload_start    = payload_start    || Defaults::PAYLOAD_START
      @ping_pattern     = ping_pattern     || Defaults::PING_PATTERN
      @data_field       = @payload_start.chomp(":")
      @buffer           = +""
      @callbacks        = Callbacks.new
      @last_event_id    = nil
      @retry_ms         = nil
    end

    # Stream state — last id/retry seen, per SSE spec semantics.
    attr_reader :last_event_id, :retry_ms

    # Raw chunk as it arrived (after normalization).
    #
    # The chunk is a string that has been normalized (UTF-8 encoded, CRLF→LF).
    # This is called for every chunk fed to the stream via <<, regardless of
    # whether the chunk contains complete frames or partial data.
    #
    # @yield [chunk] The normalized chunk string
    def on_chunk(&block)
      @callbacks.on(:chunk, &block)
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
      @callbacks.on(:frame, &block)
    end

    # Fully parsed SSE event as a {Conduit::Event}.
    #
    # This callback receives a Conduit::Event object with the following attributes:
    # - event: Event type (defaults to "message")
    # - data: Joined data field content (data lines joined by "\n")
    # - id: Last event ID from the SSE spec
    # - retry: Retry delay in milliseconds from the SSE spec
    #
    # Only called for frames that contain at least one data field.
    # Use this callback when you need access to SSE metadata (event type, id, retry).
    #
    # @yield [event] A Conduit::Event object
    def on_event(&block)
      @callbacks.on(:event, &block)
    end

    # Result of running the configured parser over an event's data.
    #
    # The parser receives ONLY the data field content (joined by "\n"), not the entire frame.
    # If you need access to other SSE fields (event type, id, retry), use on_event instead.
    #
    # If the parser raises an error and an on_error handler is registered,
    # the error is routed to on_error and this callback is NOT invoked for that event.
    #
    # @yield [parsed] Whatever your parser lambda returns
    def on_parsed(&block)
      @callbacks.on(:parsed, &block)
    end

    # Ping/comment frame.
    #
    # Ping frames are identified by the ping_pattern (default: ":").
    # These are typically used for keep-alive messages or comments.
    # Ping frames do NOT trigger on_frame or on_event callbacks.
    #
    # @yield [frame] The ping frame string
    def on_ping(&block)
      @callbacks.on(:ping, &block)
    end

    # Every parsed SSE field line. Yields (name, value) for every field, including
    # the standard ones (data/event/id/retry) and any custom fields a server emits.
    #
    # Per the SSE spec, fields are parsed one per line with the format "name: value".
    # This callback is invoked for each field line as it's parsed from the frame.
    #
    # @yield [name, value] The field name and value as strings
    def on_field(&block)
      @callbacks.on(:field, &block)
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
      @callbacks.on(:error, &block)
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

      @callbacks.emit(:chunk, chunk)
      @buffer << chunk

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
      return self if @buffer.empty?

      remainder = @buffer.slice!(0, @buffer.length)
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
      loop do
        idx = @buffer.index(@frame_separator)
        break unless idx

        frame = @buffer.slice!(0, idx + @frame_separator.length)
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

      if ping?(frame)
        @callbacks.emit(:ping, frame)
        return
      end

      @callbacks.emit(:frame, frame)

      type = nil
      data_lines = []

      parse_fields(frame).each do |name, value|
        @callbacks.emit(:field, name, value)

        case name
        when @data_field then data_lines << value
        when "event"     then type = value
        when "id"        then @last_event_id = value unless value.include?("\u0000")
        when "retry"     then @retry_ms = lenient_int(value)
        end
      end

      return if data_lines.empty?

      data = data_lines.join("\n")
      event = Event.new(
        event: type || "message",
        data: data,
        id: @last_event_id,
        retry: @retry_ms
      )

      @callbacks.emit(:event, event)

      parsed = @callbacks.call_safely(@parser, data)
      return if parsed.equal?(Callbacks::FAILED)

      @callbacks.emit(:parsed, parsed)
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
      @chunk_normalizer.call(chunk)
    end

    def sanitize(frame)
      @sanitize_pattern.call(frame)
    end

    def ping?(frame)
      frame.start_with?(@ping_pattern)
    end
  end
end
