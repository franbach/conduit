# frozen_string_literal: true

require "test_helper"

class ConduitStreamConfigBlockTest < Minitest::Test
  def test_block_form_configures_a_working_stream
    stream = ConduitSSE.new do |c|
      c.parser = ->(d) { d.upcase }
      c.stats  = true
    end

    results = []
    stream.on_parsed { |p| results << p }

    stream << "data: hello\n\n"

    assert_equal ["HELLO"], results
    assert_equal 1, stream.stats[:parsed]
  end

  def test_block_form_requires_a_parser
    assert_raises(ArgumentError) do
      ConduitSSE.new do |c|
        c.stats = true
      end
    end
  end

  def test_block_overrides_kwargs
    stream = ConduitSSE.new(parser: ->(d) { d }, stats: false) do |c|
      c.parser = ->(d) { "wrapped:#{d}" }
      c.stats  = true
    end

    results = []
    stream.on_parsed { |p| results << p }

    stream << "data: hi\n\n"

    assert_equal ["wrapped:hi"], results
    refute_nil stream.stats
  end

  def test_kwargs_seed_the_config_when_block_omits_them
    stream = ConduitSSE.new(parser: ->(d) { d.reverse }) do |c|
      c.stats = true
    end

    results = []
    stream.on_parsed { |p| results << p }

    stream << "data: abc\n\n"

    assert_equal ["cba"], results
    assert_equal 1, stream.stats[:parsed]
  end

  def test_block_form_supports_all_config_keys
    stream = ConduitSSE.new do |c|
      c.parser           = ->(d) { d }
      c.frame_separator  = "---"
      c.payload_start    = "payload:"
      c.ping_pattern     = "#"
      c.chunk_normalizer = ->(chunk) { chunk }
      c.sanitize_pattern = ->(frame) { frame.strip }
      c.stats            = true
    end

    results = []
    stream.on_parsed { |p| results << p }

    stream << "payload: hello---"

    assert_equal ["hello---"], results
  end

  def test_config_class_is_publicly_addressable
    assert_kind_of Class, ConduitSSE::Config
    config = ConduitSSE::Config.new(parser: ->(d) { d })
    assert_respond_to config, :parser=
    assert_respond_to config, :stats=
  end

  def test_config_rejects_unknown_keys
    error = assert_raises(ArgumentError) do
      ConduitSSE::Config.new(parser: ->(d) { d }, bogus: 1)
    end
    assert_match(/unknown configuration keys/, error.message)
  end

  def test_config_loads_defaults_for_unset_options
    config = ConduitSSE::Config.new(parser: ->(d) { d })
    assert_equal "\n\n",  config.frame_separator
    assert_equal "data:", config.payload_start
    assert_equal ":",     config.ping_pattern
    assert_respond_to config.chunk_normalizer, :call
    assert_respond_to config.sanitize_pattern, :call
    assert_equal false, config.stats
  end

  def test_config_validate_bang_raises_when_parser_missing
    config = ConduitSSE::Config.new
    assert_raises(ArgumentError) { config.validate! }
  end

  def test_config_finalize_computes_data_field_and_freezes
    config = ConduitSSE::Config.new(parser: ->(d) { d }, payload_start: "msg:")
    assert_nil config.data_field

    config.finalize!

    assert_equal "msg", config.data_field
    assert_predicate config, :frozen?
  end

  def test_config_finalize_validates
    config = ConduitSSE::Config.new
    assert_raises(ArgumentError) { config.finalize! }
  end

  def test_stream_exposes_frozen_config_and_state
    stream = ConduitSSE.new(parser: ->(d) { d })
    assert_kind_of ConduitSSE::Config, stream.config
    assert_predicate stream.config, :frozen?
    assert_kind_of ConduitSSE::State, stream.state
  end
end
