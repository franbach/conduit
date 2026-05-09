# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
