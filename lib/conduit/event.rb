# frozen_string_literal: true

module Conduit
  Event = Data.define(:event, :data, :id, :retry)
end
