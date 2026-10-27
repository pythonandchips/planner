# frozen_string_literal: true

module Planner
  # Everything a command needs from the outside world, so specs can inject fakes.
  Context = Data.define(:root, :agent, :stdout, :clock)
end
