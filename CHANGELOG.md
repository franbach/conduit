# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.1] - 2026-05-13

### Changed

- README polish: added a hero illustration, rewrote the OpenAI streaming
  example (the previous version double-registered `on_parsed` and
  `on_field` and undersold the gem's built-in event-type filtering),
  added a Config/State architecture section, replaced the ASCII pipeline
  diagram with a Mermaid `flowchart TD`, and renamed the block parameter
  convention from `|c|` to `|config|` in all examples for readability.
- `ConduitSSE::Config` class docstring updated to match the new
  `|config|` convention.
- Gemspec now excludes `docs/` from the packaged gem so the hero image
  doesn't bloat installs.
- Switched the README gem-version badge from `badge.fury.io` (cache-laggy,
  semi-abandoned) to `img.shields.io`, which queries RubyGems directly and
  refreshes within minutes of a release.

No code changes. Drop-in replacement for 2.0.0.

## [2.0.0] - 2026-05-12

### Breaking

- Renamed top-level module from `Conduit` to `ConduitSSE` to avoid namespace
  collisions with other `conduit`-named gems in the Ruby ecosystem. Update
  call sites from `Conduit.new(...)` to `ConduitSSE.new(...)` and from
  `Conduit::Event`/`Conduit::Inspector` to `ConduitSSE::Event`/`ConduitSSE::Inspector`.
- The canonical `require` path is now `require "conduit_sse"`. The
  bundler auto-require shim (`require "conduit-sse"`) continues to work.
- Source layout moved from `lib/conduit/` to `lib/conduit_sse/`.
- Per-stage stats tracking is now **opt-in**. Construct streams with
  `ConduitSSE.new(..., stats: true)` to enable. When disabled (the default),
  `Stream#stats` returns `nil` and the parser does zero counter bookkeeping
  per event. This eliminates any concern about stats overhead on hot paths.

### Added

- Block-form configuration for `ConduitSSE.new` / `ConduitSSE::Stream.new`.
  In addition to keyword arguments, callers can pass a block that receives
  a mutable `ConduitSSE::Config` instance:

  ```ruby
  ConduitSSE.new do |config|
    config.parser = ->(d) { JSON.parse(d) }
    config.stats  = true
  end
  ```

  Both forms can be mixed; kwargs seed the config and the block overrides.

- **`ConduitSSE::Config`**: new public class. Holds the seven parsing knobs,
  loads its own defaults, validates unknown keys, and exposes a `finalize!`
  method that runs validation, computes the derived `data_field`, and
  freezes the instance. Accessible at runtime as `stream.config`.
- **`ConduitSSE::State`**: new public class. Holds the per-stream mutable
  runtime: input buffer, callbacks registry, last event id / retry / type,
  and (when enabled) the stats counter hash. Exposes a null-object
  `#increment_stat` / `#add_fields` so the stream has no `if @stats`
  branching at counter call sites. Accessible as `stream.state`.
- **`Stream#config`** and **`Stream#state`** attr_readers for introspection.
- RBS type signatures shipped under `sig/` for the public API.
- `Architecture` README section now includes an ASCII pipeline diagram.
- Documented that `#stats` and the `Inspector` have different performance
  profiles: both are now opt-in, with `#stats` costing O(1) per event when
  enabled and `Inspector` only active when attached.

## [1.0.0] - 2026-05-10

### Added

- `buffer_size` method for monitoring internal buffer size in bytes
- `stats` method for stream statistics (chunk, frame, event, parsed, ping, field, error, avg_fields_per_frame)
- Per-callback event filtering with `on_event(type:)` and `on_parsed(type:)` parameters
- Custom configuration tests for chunk_normalizer, payload_start, frame_separator, ping_pattern, and sanitize_pattern
- CI and gem version badges to README

### Changed

- Switched from global event filter to per-callback filtering for more flexibility
- Improved README documentation with clearer finish usage instructions
- Clarified design philosophy to emphasize that Conduit works in any Ruby application, not just Rails
- Updated finish documentation to clarify it's a defensive measure for edge cases

## [0.1.1] - 2026-05-08

### Added

- Shim file `lib/conduit-sse.rb` to allow automatic requiring when gem is added to Gemfile
- Renamed gem from `conduit` to `conduit-sse` due to name conflict on RubyGems

## [0.1.0] - 2026-05-08

### Added

- Initial release of Conduit, a lightweight, zero-dependency Ruby gem for parsing Server-Sent Events (SSE) streams
- Flexible callback-based architecture for processing real-time server push data
- Custom parser support for transforming event data into any shape
- SSE spec compliant parsing following the HTML Server-Sent Events specification
- Built-in inspector for development and troubleshooting
- Robust error handling to prevent stream interruption
- Granular access callbacks (`on_frame`, `on_field`) for non-standard SSE implementations
- Support for streaming AI responses, real-time analytics, and live updates
- Comprehensive test coverage with fuzz testing
