# frozen_string_literal: true

module ConduitSSE
  # Attach to a ConduitSSE::Stream to log every layer of activity to an IO.
  # Intended for development/debugging only.
  #
  #   stream = ConduitSSE.new(parser: ->(d) { JSON.parse(d) })
  #   ConduitSSE::Inspector.attach(stream)
  #
  # Pass io: to redirect (e.g. a StringIO in tests, a file, $stderr).
  class Inspector
    def self.attach(stream, io: $stdout)
      new(stream, io: io).attach
    end

    attr_reader :counts

    def initialize(stream, io:)
      @stream = stream
      @io     = io
      @counts = Hash.new(0)
    end

    def attach
      log_chunks
      log_frames
      log_fields
      log_pings
      log_events
      log_parsed
      log_errors
      self
    end

    # Print a one-line summary of everything seen so far.
    def summary
      @io.puts(
        "[SUMMARY] " \
        "chunks=#{@counts[:chunk]} " \
        "frames=#{@counts[:frame]} " \
        "events=#{@counts[:event]} " \
        "parsed=#{@counts[:parsed]} " \
        "pings=#{@counts[:ping]} " \
        "fields=#{@counts[:field]} " \
        "errors=#{@counts[:error]} " \
        "last_event_id=#{@stream.last_event_id.inspect} " \
        "retry_ms=#{@stream.retry_ms.inspect}"
      )
    end

    private

    def log_chunks
      @stream.on_chunk do |chunk|
        @counts[:chunk] += 1
        @io.puts "\n[CHUNK ##{@counts[:chunk]} | #{chunk.bytesize} bytes]"
        @io.puts chunk
      end
    end

    def log_frames
      @stream.on_frame do |frame|
        @counts[:frame] += 1
        @io.puts "\n[FRAME ##{@counts[:frame]} | #{frame.bytesize} bytes]"
        @io.puts frame
      end
    end

    def log_fields
      @stream.on_field do |name, value|
        @counts[:field] += 1
        @io.puts "-->[FIELD] #{name}=#{value.inspect}"
      end
    end

    def log_pings
      @stream.on_ping do |frame|
        @counts[:ping] += 1
        @io.puts "\n[PING ##{@counts[:ping]}] #{frame.inspect}"
      end
    end

    def log_events
      @stream.on_event do |event|
        @counts[:event] += 1
        @io.puts "\n[EVENT ##{@counts[:event]}] " \
                 "event=#{event.event.inspect} " \
                 "id=#{event.id.inspect} " \
                 "retry=#{event.retry.inspect}"
        @io.puts "  data: #{event.data.inspect}"
      end
    end

    def log_parsed
      @stream.on_parsed do |result|
        @counts[:parsed] += 1
        @io.puts "[PARSED ##{@counts[:parsed]}] #{result.inspect}"
      end
    end

    def log_errors
      @stream.on_error do |error|
        @counts[:error] += 1
        @io.puts "\n[ERROR ##{@counts[:error]}] #{error.class}: #{error.message}"
      end
    end
  end
end
