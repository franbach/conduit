# frozen_string_literal: true

module ConduitSSE
  Event = Data.define(:event, :data, :id, :retry)
end
