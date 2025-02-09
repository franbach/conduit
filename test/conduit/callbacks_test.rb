# frozen_string_literal: true

require "test_helper"

class ConduitCallbacksTest < Minitest::Test
  def setup
    @callbacks = Conduit::Callbacks.new
  end

  # Composition

  def test_emit_with_no_subscribers_is_noop
    @callbacks.emit(:frame, "x") # must not raise
  end

  def test_single_subscriber_receives_args
    received = []
    @callbacks.on(:frame) { |f| received << f }

    @callbacks.emit(:frame, "hello")

    assert_equal ["hello"], received
  end

  def test_multiple_subscribers_fire_in_registration_order
    order = []
    @callbacks.on(:frame) { |_| order << :first }
    @callbacks.on(:frame) { |_| order << :second }
    @callbacks.on(:frame) { |_| order << :third }

    @callbacks.emit(:frame, "x")

    assert_equal %i[first second third], order
  end

  def test_subscribers_isolated_per_name
    frames = []
    events = []
    @callbacks.on(:frame) { |f| frames << f }
    @callbacks.on(:event) { |e| events << e }

    @callbacks.emit(:frame, "f")
    @callbacks.emit(:event, "e")

    assert_equal ["f"], frames
    assert_equal ["e"], events
  end

  # Error routing

  def test_raising_subscriber_without_error_handler_re_raises
    @callbacks.on(:frame) { |_| raise "boom" }

    assert_raises(RuntimeError) { @callbacks.emit(:frame, "x") }
  end

  def test_raising_subscriber_routes_to_error_handler
    errors = []
    @callbacks.on(:error) { |e| errors << e }
    @callbacks.on(:frame) { |_| raise "boom" }

    @callbacks.emit(:frame, "x") # must not raise

    assert_equal 1, errors.size
    assert_kind_of RuntimeError, errors.first
    assert_equal "boom", errors.first.message
  end

  def test_error_handler_raising_bubbles_and_does_not_loop
    @callbacks.on(:error) { |_| raise "error handler exploded" }

    assert_raises(RuntimeError) { @callbacks.emit(:error, StandardError.new("x")) }
  end

  def test_subsequent_emits_continue_after_routed_error
    errors = []
    frames = []
    @callbacks.on(:error) { |e| errors << e }
    @callbacks.on(:frame) do |f|
      raise "boom" if f == "bad"

      frames << f
    end

    @callbacks.emit(:frame, "good")
    @callbacks.emit(:frame, "bad")
    @callbacks.emit(:frame, "good again")

    assert_equal ["good", "good again"], frames
    assert_equal 1, errors.size
  end

  # call_safely + FAILED sentinel

  def test_call_safely_returns_callable_result_on_success
    result = @callbacks.call_safely(->(x) { x * 2 }, 21)

    assert_equal 42, result
  end

  def test_call_safely_returns_falsy_values_unchanged
    assert_nil @callbacks.call_safely(->(_) { nil }, :anything)
    assert_equal false, @callbacks.call_safely(->(_) { false }, :anything)
  end

  def test_call_safely_re_raises_when_no_error_handler
    assert_raises(RuntimeError) do
      @callbacks.call_safely(->(_) { raise "boom" }, :x)
    end
  end

  def test_call_safely_returns_failed_sentinel_when_error_routed
    @callbacks.on(:error) { |_| } # swallow

    result = @callbacks.call_safely(->(_) { raise "boom" }, :x)

    assert_same Conduit::Callbacks::FAILED, result
  end

  def test_failed_sentinel_is_stable_across_calls
    @callbacks.on(:error) { |_| }

    a = @callbacks.call_safely(->(_) { raise "a" }, :x)
    b = @callbacks.call_safely(->(_) { raise "b" }, :x)

    assert_same a, b
    assert_same Conduit::Callbacks::FAILED, a
  end
end
