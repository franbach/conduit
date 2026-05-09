# frozen_string_literal: true

require "test_helper"

class ConduitEventTest < Minitest::Test
  def test_construction_with_keyword_args
    e = Conduit::Event.new(event: "message", data: "hi", id: "1", retry: 5000)

    assert_equal "message", e.event
    assert_equal "hi",      e.data
    assert_equal "1",       e.id
    assert_equal 5000,      e.retry
  end

  def test_value_equality
    a = Conduit::Event.new(event: "m", data: "x", id: nil, retry: nil)
    b = Conduit::Event.new(event: "m", data: "x", id: nil, retry: nil)

    assert_equal a, b
  end

  def test_is_immutable
    e = Conduit::Event.new(event: "m", data: "x", id: nil, retry: nil)

    assert_raises(NoMethodError) { e.data = "other" }
  end

  def test_with_returns_a_modified_copy
    e = Conduit::Event.new(event: "m", data: "x", id: nil, retry: nil)
    other = e.with(data: "y")

    assert_equal "x", e.data
    assert_equal "y", other.data
  end
end
