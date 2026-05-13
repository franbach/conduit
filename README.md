# ConduitSSE

![CI](https://github.com/franbach/conduit/actions/workflows/main.yml/badge.svg)
[![Gem Version](https://img.shields.io/gem/v/conduit-sse.svg)](https://rubygems.org/gems/conduit-sse)
[![Downloads](https://img.shields.io/gem/dt/conduit-sse.svg)](https://rubygems.org/gems/conduit-sse)

ConduitSSE is a lightweight, zero-dependency Ruby gem for parsing Server-Sent Events (SSE) streams. It provides a flexible callback-based architecture for processing real-time server push data with full control over every stage of the parsing pipeline.

## Design Philosophy

ConduitSSE acts as a **conductor**, it parses SSE streams and routes events to your callbacks, but it doesn't manage or control the SSE stream itself. You control the HTTP connection, reconnection logic, and stream lifecycle. ConduitSSE handles the parsing and event routing.

This separation keeps ConduitSSE lightweight and flexible. You can use it with any HTTP client **(Net::HTTP, HTTParty, Faraday, etc.)** and implement your own reconnection logic. ConduitSSE stays out of the way.

## Why ConduitSSE?

Building real-time applications with SSE shouldn't require wrestling with complex parsing logic or sacrificing performance for convenience. ConduitSSE gives you:

**🎯 Zero Dependencies** - Drop it into any Ruby project without worrying about dependency hell. Pure Ruby, no external gems. it works in any Ruby application (Rails, Sinatra, plain scripts, background jobs, etc.) and is not tied to any specific framework.

**🔧 Complete Control** - Hook into every stage of the parsing pipeline with callbacks. Whether you need to transform data, forward to services, emit to frontends, or add observability. ConduitSSE adapts to your architecture.

**📡 Production Ready** - Built for real-world use with robust error handling, SSE spec compliance, and a built-in inspector for debugging. Streams from AI providers, or any SSE endpoint just work.

**⚡ Flexible Parsers** - Your parser lambda can do anything: JSON parsing, YAML loading, custom transformations, or domain-specific logic. You're not locked into any data shape.

**🔍 Granular Access** - Need to handle non-standard SSE fields? Want raw frame access? ConduitSSE provides both spec-compliant callbacks (`on_event`, `on_parsed`) and low-level access (`on_frame`, `on_field`) for maximum flexibility.

Perfect for streaming AI responses, real-time analytics, live updates, and any application that needs to process server-push events efficiently.

## Features

- **Zero dependencies** - Pure Ruby, no external gems required
- **Flexible callback system** - Hook into every stage of the parsing pipeline
- **Custom parsers** - Transform event data into any shape your application needs
- **SSE spec compliant** - Follows the HTML Server-Sent Events specification
- **Debugging support** - Built-in inspector for development and troubleshooting
- **Error handling** - Robust error routing to prevent stream interruption

## Installation

Install the gem and add to your application's Gemfile:

```bash
bundle add conduit-sse
```

If bundler is not being used, install the gem directly:

```bash
gem install conduit-sse
```

## Usage

### Configuring a Stream

The canonical way to build a stream is with a configuration block. The block
receives a mutable {ConduitSSE::Config} that exposes every knob as a setter:

```ruby
stream = ConduitSSE.new do |c|
  c.parser          = ->(d) { JSON.parse(d) }
  c.stats           = true
  c.frame_separator = "\r\n\r\n"
end
```

For one- or two-knob setups, plain keyword arguments are equally fine:

```ruby
stream = ConduitSSE.new(parser: ->(d) { JSON.parse(d) }, stats: true)
```

The two forms can also be combined — kwargs seed the config, the block then
mutates whatever it wants on top:

```ruby
stream = ConduitSSE.new(parser: ->(d) { d }) do |c|
  c.stats = true
end
```

The full list of settings (with defaults) lives on `ConduitSSE::Config`:
`parser` (required), `chunk_normalizer`, `frame_separator`, `payload_start`,
`ping_pattern`, `sanitize_pattern`, `stats`. Unknown keys raise an explicit
`ArgumentError` at construction time, so typos surface immediately.

### Basic Example

At its core, ConduitSSE processes SSE data chunks and emits callbacks at each stage:

```ruby
require "conduit_sse"

# Create a stream with a parser that transforms event data
stream = ConduitSSE.new do |c|
  c.parser = ->(data) { JSON.parse(data) }
end

# Subscribe to parsed events
stream.on_parsed do |parsed|
  puts "Received: #{parsed}"
end

# Feed data chunks (typically from an HTTP stream)
stream << "data: {\"message\": \"hello\"}\n\n"
```

### Real-World Example with Net::HTTP

Here's a complete example connecting to an SSE endpoint:

```ruby
require "conduit_sse"
require "net/http"
require "uri"
require "json"

stream = ConduitSSE.new do |c|
  c.parser = ->(d) { JSON.parse(d) rescue d }
end

stream.on_parsed do |parsed|
  next unless parsed.is_a?(Hash)
  puts "#{parsed['wiki']}: #{parsed['title']} by #{parsed['user']}"
end

uri = URI("https://stream.wikimedia.org/v2/stream/recentchange")

Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
  http.read_timeout = nil # disable read timeout for SSE

  http.request(Net::HTTP::Get.new(uri, "Accept" => "text/event-stream")) do |response|
    response.read_body { |chunk| stream << chunk }
  end
end
```

### OpenAI Streaming Example

Here's a complete example using ConduitSSE to stream responses from OpenAI's Responses API:

```ruby
require "conduit_sse"
require "net/http"
require "uri"
require "json"

# Set your OpenAI API key
api_key = "your-api-key-here"

# Create the stream with a parser that extracts the delta content
stream = ConduitSSE.new do |c|
  c.parser = ->(data) { JSON.parse(data) }
end

result = +""

# Approach 1: Use on_parsed to extract delta after JSON parsing
# Since OpenAI sends structured JSON in the data field, the parser converts it to a Hash,
# making it easy to extract the delta content directly.
stream.on_parsed do |parsed_data|
  type = parsed_data["type"]

  if type == "response.output_text.delta"
    delta = parsed_data["delta"]
    if delta
      puts "parsed delta: #{delta}"
      result += delta

      # You can also emit the delta to a frontend app here if you will.
      # emit_to_frontend(delta)
    end
  end

  if type == "response.completed"
    puts "\n\nResult: #{result}"
  end
end

# Approach 2: Use on_field for more granular control
# This approach gives you access to the raw field values before JSON parsing,
# useful if you need to inspect or modify the raw data field content.
stream.on_field do |name, value|
  if name == "data"
    data = JSON.parse(value)
    type = data["type"]

    if type == "response.output_text.delta"
      delta = data["delta"]
      if delta
        puts "delta: #{delta}"
        result += delta

        # You can also emit the delta to a frontend app here if you will.
        # emit_to_frontend(delta)
      end
    end

    if type == "response.completed"
      puts "\n\nResult: #{result}"
    end
  end
end

# Make the streaming request
uri = URI("https://api.openai.com/v1/responses")
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

request = Net::HTTP::Post.new(uri)
request["Content-Type"] = "application/json"
request["Authorization"] = "Bearer #{api_key}"

request.body = JSON.generate({
  model: "gpt-4.1-mini",
  stream: true, # Enable streaming
  input: [
    { role: "user", content: "Write a haiku about programming" }
  ]
})

http.request(request) do |response|
  response.read_body do |chunk|
    stream << chunk
  end
end
```

**Note:** OpenAI's Responses API uses `data:` fields with JSON payloads. The response format includes a `type` field to identify event types (`response.output_text.delta` for streaming text chunks, `response.completed` when the stream finishes). The `parser` extracts the data content from each frame as it arrives, allowing you to display the response in real-time.

**Important:** Callbacks must be registered **before** the HTTP request starts. This ensures the stream knows what to do with incoming data as soon as chunks arrive.

### Callback System

ConduitSSE provides callbacks at every stage of processing:

```ruby
stream = ConduitSSE.new { |c| c.parser = ->(data) { data } }

# Raw chunk as it arrived (after normalization)
stream.on_chunk do |chunk|
  puts "Chunk received: #{chunk.bytesize} bytes"
end

# Complete frame text (after sanitization)
stream.on_frame do |frame|
  puts "Frame: #{frame}"
end

# Individual SSE field lines
stream.on_field do |name, value|
  puts "Field: #{name}=#{value}"
end

# Fully parsed SSE event
stream.on_event do |event|
  puts "Event type: #{event.event}, id: #{event.id}"
end

# Result of your parser
stream.on_parsed do |parsed|
  puts "Parsed: #{parsed}"
end

# Ping/comment frames
stream.on_ping do |frame|
  puts "Ping received"
end

# Errors from callbacks or parser
stream.on_error do |error|
  puts "Error: #{error.message}"
end
```

### Filtering Events

Filter events by type directly on callback registration:

```ruby
stream = ConduitSSE.new { |c| c.parser = ->(data) { data } }

# Only process "message" events in this callback
stream.on_event(type: "message") do |event|
  puts "Message: #{event.data}"
end

# Process multiple event types
stream.on_event(type: %w[message update]) do |event|
  puts "Event: #{event.event}, Data: #{event.data}"
end

# Filter on_parsed callback
stream.on_parsed(type: "message") do |parsed|
  puts "Parsed message: #{parsed}"
end

# Register multiple callbacks with different filters
stream.on_event(type: "message") { |e| puts "Message: #{e.data}" }
stream.on_event(type: "update") { |e| puts "Update: #{e.data}" }

# Callbacks without filters receive all events
stream.on_event { |e| puts "All events: #{e.event}" }
```

The filter is per-callback, so you can have different handlers for different event types. Low-level callbacks (`on_frame`, `on_field`) are not affected by event type filters.

### Understanding Callback Differences

It's important to understand the distinction between `on_frame`, `on_event`, and `on_parsed`/`each`:

**`on_frame`** - Receives the raw frame text (string) after sanitization, regardless of whether it produces an event:

```ruby
stream.on_frame do |frame|
  # frame is a string like "event: message\ndata: hello\nid: 123\n\n"
  puts frame
end
```

**`on_event`** - Receives a fully parsed `ConduitSSE::Event` object with SSE metadata:

```ruby
stream.on_event do |event|
  # event is a ConduitSSE::Event object
  puts event.event  # Event type (e.g., "message")
  puts event.data   # Data field content (joined data lines)
  puts event.id     # Last event ID (if sent by server)
  puts event.retry  # Retry delay in ms (if sent by server)
end
```

**`each` / `on_parsed`** - Receives the result of your custom parser (the `parser:` lambda):

```ruby
stream = ConduitSSE.new { |c| c.parser = ->(data) { JSON.parse(data) } }

stream.each do |parsed|
  # parsed is whatever your parser returns
  # In this case, a Hash from JSON.parse(data)
  puts parsed
end
```

**The processing flow:**

1. Raw chunk arrives → `on_chunk` (string)
2. Chunks are buffered and split into frames
3. Frame is sanitized → `on_frame` (string)
4. Frame is parsed into SSE fields → `on_field` (name, value pairs)
5. Event object is constructed → `on_event` (ConduitSSE::Event)
6. Your parser transforms the data → `on_parsed`/`each` (your custom output)

**Key nuance:** The parser receives **only the data field content** (joined by newlines), not the entire frame. If you need access to other fields (event type, id, retry), use `on_event` instead.

### Callback Philosophy

ConduitSSE's callback system is designed around two complementary approaches:

**SSE-Spec Callbacks** (`on_event`, `on_parsed`)

- These callbacks are tied to the SSE specification
- `on_event` receives a structured `ConduitSSE::Event` object with standard SSE fields (event type, data, id, retry)
- `on_parsed` receives the output of your custom parser, which operates on the data field content
- Use these when working with spec-compliant SSE streams or when you want structured, predictable data

**Granular Control Callbacks** (`on_frame`, `on_field`)

- These provide low-level access to the raw stream data, independent of SSE specification
- `on_frame` gives you the complete frame text before field parsing
- `on_field` gives you individual field lines as they're parsed, including custom/non-standard fields
- Use these when dealing with non-standard SSE implementations, custom field names, or when you need complete control over the parsing process

**Choosing between approaches:**

- If the SSE stream follows the specification, `on_event` with `ConduitSSE::Event` provides a structured, spec-compliant representation of the event
- If the frame deviates from the SSE specification or uses custom/non-standard fields, `on_frame` gives you raw access to the frame content, allowing you to handle it independently of the specification
- Use `on_field` to inspect individual fields when you need to handle custom or non-standard field names
- Your `parser` lambda can implement any logic needed: JSON parsing, YAML loading, custom transformations, validation, or domain-specific processing

### Common Use Cases

ConduitSSE's callback system makes it easy to integrate SSE streams into your application architecture:

**Forwarding to Services**

```ruby
stream.on_parsed do |parsed|
  # Forward parsed events to a message queue, database, or external service
  MessageQueue.publish("events", parsed)
end
```

**Emitting to Frontend Applications**

```ruby
stream.on_parsed do |parsed|
  # Stream real-time updates to connected WebSocket clients
  WebSocketBroadcaster.broadcast("updates", parsed)
end
```

**Adding Observability**

```ruby
stream.on_event do |event|
  # Track metrics for monitoring
  Metrics.increment("sse.events.received", tags: { type: event.event })
end

stream.on_error do |error|
  # Log errors for debugging
  Logger.error("SSE processing error", error: error.message)
end
```

**Data Transformation**

```ruby
stream = ConduitSSE.new do |c|
  c.parser = ->(data) {
    # Transform raw data into your domain models
    raw = JSON.parse(data)
    MyDomainModel.new(raw)
  }
end

stream.on_parsed do |model|
  # Work with your domain objects directly
  model.process!
end
```

**Multi-Consumer Pattern**

```ruby
# Multiple callbacks can handle the same event
stream.on_parsed do |parsed|
  # Consumer 1: Update cache
  Cache.set(parsed["id"], parsed)
end

stream.on_parsed do |parsed|
  # Consumer 2: Trigger webhook
  WebhookService.trigger(parsed)
end

stream.on_parsed do |parsed|
  # Consumer 3: Update analytics
  Analytics.track("event_received", parsed)
end
```

### Event Object

Parsed events are returned as `ConduitSSE::Event` objects with the following attributes:

- `event` - Event type (defaults to "message")
- `data` - The event data string
- `id` - Last event ID (from SSE spec)
- `retry` - Retry delay in milliseconds (from SSE spec)

```ruby
stream.on_event do |event|
  puts "Type: #{event.event}"
  puts "Data: #{event.data}"
  puts "ID: #{event.id}"
  puts "Retry: #{event.retry}ms" if event.retry
end
```

### Customization Options

Every setting lives on `ConduitSSE::Config` and can be set via the block:

```ruby
stream = ConduitSSE.new do |c|
  # Required: A callable that receives the joined data field content (string)
  # and returns whatever shape your application needs (e.g., JSON.parse, YAML.load).
  c.parser = ->(data) { JSON.parse(data) }

  # Optional: Transforms incoming chunks before processing.
  # Default: UTF-8 conversion + CRLF→LF normalization.
  # NOTE: Replacing the default fully replaces UTF-8 handling; if you need it,
  # implement it yourself.
  c.chunk_normalizer = ->(chunk) { chunk.upcase }

  # Optional: Delimiter that separates frames in the stream.
  # Default: "\n\n"
  c.frame_separator = "\r\n\r\n"

  # Optional: Prefix used to identify the data field.
  # The trailing ":" is stripped to derive the field name.
  # Default: "data:"
  c.payload_start = "data:"

  # Optional: Pattern identifying ping/comment frames.
  # Default: ":"
  c.ping_pattern = ":"

  # Optional: Cleans or validates frame content after splitting.
  # Default: UTF-8 conversion + strip.
  # NOTE: Replacing the default fully replaces UTF-8 handling.
  c.sanitize_pattern = ->(frame) { frame.strip }

  # Optional: Enables the per-stage counter hash exposed via #stats.
  # Default: false (off; #stats returns nil).
  c.stats = true
end
```

The same options also work as keyword arguments to `ConduitSSE.new(...)` if you
prefer a compact one-liner.

### Using `each` for Enumerable Interface

For a simpler interface, use `each` to iterate over parsed events:

```ruby
stream = ConduitSSE.new { |c| c.parser = ->(data) { data } }

stream.each do |parsed|
  puts "Received: #{parsed}"
end

# Feed data
stream << "data: hello\n\n"
stream << "data: world\n\n"
```

### Accessing SSE State

ConduitSSE tracks SSE spec state that you can access directly on the stream
(or through the underlying `stream.state` object, see
[Architecture: Config and State](#architecture-config-and-state)):

```ruby
stream = ConduitSSE.new { |c| c.parser = ->(data) { data } }

stream << "id: 123\ndata: hello\n\n"

puts stream.last_event_id  # => "123"
puts stream.retry_ms       # => nil (unless server sends retry field)
```

### Monitoring Stream Activity

ConduitSSE provides read-only methods for monitoring stream activity without the overhead of the Inspector:

```ruby
stream = ConduitSSE.new { |c| c.parser = ->(data) { data } }

# Check buffer size — always available, zero-cost (one bytesize lookup).
stream << "data: hello"
puts stream.buffer_size  # => buffer size in bytes
```

#### Stats are opt-in

Per-stage counters are **disabled by default**. Set `c.stats = true` (or pass
`stats: true` as a kwarg) to enable them. When stats are off, `#stats` returns
`nil` and the parser performs no counter bookkeeping per event — important on
hot paths at high event rates.

```ruby
# Default: stats disabled
stream = ConduitSSE.new { |c| c.parser = ->(data) { data } }
stream << "data: hello\n\n"
stream.stats  # => nil

# Opt in:
stream = ConduitSSE.new do |c|
  c.parser = ->(data) { data }
  c.stats  = true
end
stream << "data: hello\n\n"
stream.stats
# => { chunk: 1, frame: 1, event: 1, parsed: 1, ping: 0, field: 1, error: 0, avg_fields_per_frame: 1.0 }
```

**Statistics keys:**

- `chunk` - Number of chunks fed to the stream via `<<`
- `frame` - Number of complete frames processed
- `event` - Number of SSE events emitted (frames with data fields)
- `parsed` - Number of successful parser results
- `ping` - Number of ping/comment frames detected
- `field` - Number of SSE field lines parsed (data, event, id, retry, etc.)
- `error` - Number of errors raised by callbacks or the parser
- `avg_fields_per_frame` - Average number of fields per frame

### Handling Stream Completion

Use `finish` (or its alias `close`) once at the end of the stream to process any remaining data in the buffer:

```ruby
stream = ConduitSSE.new { |c| c.parser = ->(data) { JSON.parse(data) } }

http.request(request) do |response|
  response.read_body do |chunk|
    stream << chunk
  end
end

# Call finish once at the end as a just-in-case measure
stream.finish
```

**Important notes:**

- Call `finish` **once** at the end of the stream, not on each frame
- Frames are automatically processed as they arrive via `<<`
- `finish` is for the edge case where the HTTP connection closes without a trailing `\n\n`
- If the buffer is empty, `finish` does nothing (safe to call)
- Many SSE servers send proper frame separators, so you may not need `finish` at all, it's a defensive measure

### Error Handling

Errors in callbacks are routed to the `on_error` handler, preventing stream interruption:

```ruby
stream = ConduitSSE.new { |c| c.parser = ->(data) { JSON.parse(data) } }

stream.on_error do |error|
  puts "Caught error: #{error.message}"
  # Stream continues processing
end

stream.on_parsed do |parsed|
  # If this raises, it's caught by on_error
  process_data(parsed)
end

stream << "data: invalid json\n\n"  # Parser fails, but stream continues
```

### Debugging with Inspector

Use the built-in inspector to log all stream activity during development:

```ruby
require "net/http"
require "uri"
require "json"

stream = ConduitSSE.new { |c| c.parser = ->(data) { JSON.parse(data) } }

# Attach inspector to log everything to stdout
ConduitSSE::Inspector.attach(stream)

# Or log to a different IO
ConduitSSE::Inspector.attach(stream, io: $stderr)

# You'll see [CHUNK], [FRAME], [FIELD], [EVENT], [PARSED] lines as data flows.
# Wikimedia tends to emit event:, id:, data: and occasional : ping keep-alives.
uri = URI("https://stream.wikimedia.org/v2/stream/recentchange")

Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
  http.read_timeout = nil # disable read timeout for SSE

  http.request(Net::HTTP::Get.new(uri, "Accept" => "text/event-stream")) do |response|
    response.read_body { |chunk| stream << chunk }
  end
end

```

The inspector logs:

- Chunks with byte counts
- Frames with byte counts
- Individual fields
- Pings
- Events with metadata
- Parsed results
- Errors

### Multiple Callbacks

You can register multiple callbacks for the same event type:

```ruby
stream = ConduitSSE.new { |c| c.parser = ->(data) { data } }

stream.on_parsed do |parsed|
  puts "Handler 1: #{parsed}"
end

stream.on_parsed do |parsed|
  puts "Handler 2: #{parsed}"
end

stream << "data: hello\n\n"
# Both handlers execute in registration order
```

### Custom Field Handling

ConduitSSE emits all SSE fields, including custom ones:

```ruby
stream = ConduitSSE.new { |c| c.parser = ->(data) { data } }

stream.on_field do |name, value|
  case name
  when "data"
    puts "Data: #{value}"
  when "custom-field"
    puts "Custom: #{value}"
  end
end

stream << "data: hello\ncustom-field: value\n\n"
```

## Architecture

ConduitSSE processes data through a nine-stage pipeline. Each stage has a
dedicated callback hook so you can tap in at whatever level matches the
server's behavior (spec-compliant or not):

```mermaid
flowchart TD
    In([HTTP body chunks]) --> S1

    S1["1 · Chunk Normalize<br/><sub>UTF-8, CRLF→LF</sub>"] -.->|on_chunk| CB1(["chunk"])
    S1 --> S2["2 · Buffer<br/><sub>accumulate</sub>"]
    S2 --> S3["3 · Frame Split<br/><sub>\\n\\n boundary</sub>"]
    S3 --> S4["4 · Sanitize<br/><sub>strip, utf-8</sub>"]
    S4 --> S5{{"5 · Ping Detect"}}
    S5 -.->|on_ping<br/>short-circuit| CB2(["ping frame"])
    S5 -->|not a ping| S5b["on_frame"]
    S5b -.->|on_frame| CB3(["frame"])
    S5b --> S6["6 · Field Parse<br/><sub>spec §9.2.6</sub>"]
    S6 -.->|on_field<br/>every line| CB4(["name, value"])
    S6 --> S7["7 · Event Construct<br/><sub>event / id / retry</sub>"]
    S7 -.->|on_event| CB5(["ConduitSSE::Event"])
    S7 --> S8["8 · Parser Apply<br/><sub>your lambda</sub>"]
    S8 -.->|on_parsed| CB6(["parser result"])

    Err(["on_error(exception)"])
    S1 & S4 & S6 & S7 & S8 -.->|any raise| Err

    classDef stage fill:#1f2937,stroke:#60a5fa,color:#f9fafb;
    classDef cb fill:#064e3b,stroke:#34d399,color:#ecfdf5;
    classDef err fill:#7f1d1d,stroke:#f87171,color:#fef2f2;
    class S1,S2,S3,S4,S5,S5b,S6,S7,S8 stage;
    class CB1,CB2,CB3,CB4,CB5,CB6 cb;
    class Err err;
```

Stage-by-stage:

- **1. Chunk Normalization** — Raw chunks are normalized (UTF-8 conversion, CRLF→LF).
- **2. Buffering** — Chunks are buffered until frame boundaries are found.
- **3. Frame Splitting** — Frames are split by the separator (default: `\n\n`).
- **4. Sanitization** — Frames are sanitized (default: strip whitespace).
- **5. Ping Detection** — Ping/comment frames are identified and short-circuited.
- **6. Field Parsing** — SSE fields are parsed per the HTML spec.
- **7. Event Construction** — Events are built from parsed fields.
- **8. Parser Application** — Your custom parser transforms event data.
- **9. Callback Emission** — Callbacks are invoked at each stage.

### Architecture: Config and State

Internally a `Stream` is the composition of two distinct objects, each with a
different lifecycle:

```text
ConduitSSE::Stream                          ← glues the two together
  ├─ #config : ConduitSSE::Config           ← what to do (frozen after construction)
  └─ #state  : ConduitSSE::State            ← where we are (mutated per event)
```

- **`ConduitSSE::Config`** holds the seven parsing knobs (parser, normalizers,
  separators, patterns, the `stats` flag). It's populated via kwargs and/or
  the configuration block, validated, has its derived `data_field` computed,
  and is then **frozen** — accidental mid-stream mutation raises
  `FrozenError`. Both forms of public access work the same way:

  ```ruby
  stream.config.parser           # => your parser lambda
  stream.config.frame_separator  # => "\n\n"
  stream.config.frozen?          # => true
  ```

- **`ConduitSSE::State`** holds the per-stream mutable runtime: the input
  buffer, the registered `Callbacks`, `last_event_id` / `retry_ms` /
  `last_event_type` as they're observed on the wire, and (when enabled) the
  stats counter hash. It's accessible via `stream.state` for inspection:

  ```ruby
  stream.state.buffer_size       # bytes pending in the buffer
  stream.state.last_event_id     # last `id:` seen
  stream.state.stats_enabled?    # true iff stats: true was passed
  ```

The `#last_event_id`, `#retry_ms`, `#buffer_size`, and `#stats` methods on
`Stream` are thin forwarders to the underlying `State`, so you rarely need to
reach into `stream.state` directly — but it's there when you want to
introspect a stream from the outside (tests, dashboards, custom tooling).

### Performance Notes: Stats vs. Inspector

The `#stats` hash and the `ConduitSSE::Inspector` are **not** the same mechanism
and have very different performance profiles:

- **`#stats` is opt-in** (`c.stats = true` in the block, or `stats: true` as a
  kwarg). When disabled (the default), `#stats` returns `nil` and the stream
  performs **zero** per-event counter bookkeeping. The State object exposes
  `#increment_stat` and `#add_fields` as null-object methods that return
  immediately when stats are off, so there is no per-call-site `if @stats`
  branching in the hot path. When enabled, the cost is O(1) per event: a
  handful of `Hash#[]+=` increments on a `Hash.new(0)` inside
  `process_frame`. Either way: no string formatting, no I/O. Safe to leave
  on in production if you want the metrics; safe to leave off if you don't.
- **`ConduitSSE::Inspector` is strictly opt-in.** It only does work after you
  call `ConduitSSE::Inspector.attach(stream)`. Attachment registers regular
  user callbacks (`on_chunk`, `on_frame`, …) that do `inspect`, string
  interpolation, and `IO#puts`. Those are **not** zero-cost — keep the
  inspector off in production and use it for local debugging only.
- **Unregistered callbacks are free.** `Callbacks#emit` returns immediately
  when no handler is registered for a given stage; there is no hidden
  per-stage allocation or dispatch cost for callbacks you didn't set up.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Contributions of all kinds are welcome on GitHub at https://github.com/franbach/conduit.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
