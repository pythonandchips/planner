# frozen_string_literal: true

module Planner
  # Everything a command needs from the outside world, so specs can inject fakes.
  Context = Data.define(:root, :home, :skills_dir, :agent, :stdin, :stdout, :clock)
end
