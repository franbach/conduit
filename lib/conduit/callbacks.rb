# frozen_string_literal: true

module Conduit
  class Callbacks
    FAILED = Object.new.freeze

    def initialize
      @callbacks = {}
    end

    def on(name, &block)
      @callbacks[name] = compose(@callbacks[name], block)
    end

    def emit(name, *args)
      callback = @callbacks[name]
      return if callback.nil?

      callback.call(*args)
    rescue StandardError => e
      raise unless name != :error && @callbacks[:error]

      @callbacks[:error].call(e)
    end

    def call_safely(callable, *args)
      callable.call(*args)
    rescue StandardError => e
      raise unless @callbacks[:error]

      @callbacks[:error].call(e)
      FAILED
    end

    private

    def compose(previous, current)
      return previous if current.nil?
      return current if previous.nil?

      proc do |*args|
        previous.call(*args)
        current.call(*args)
      end
    end
  end
end
