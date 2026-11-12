# frozen_string_literal: true

require 'rubocop'

module RuboCop
  module Cop
    module Planner
      # Flags compound matchers chained with `.and` or `&` (writing-rspec: no compound matchers).
      class NoCompoundMatcher < Base
        MSG = 'Write one `expect` per line instead of a compound matcher, and tag the example `:aggregate_failures`.'

        RESTRICT_ON_SEND = %i[to not_to to_not].freeze

        # @!method compound_matcher(node)
        def_node_matcher :compound_matcher, <<~PATTERN
          (send {(send nil? :expect ...) (block (send nil? :expect) ...) (send nil? :is_expected)}
            {:to :not_to :to_not} $(send _ {:and :&} _) ...)
        PATTERN

        def on_send(node)
          compound_matcher(node) { |matcher| add_offense(matcher) }
        end
      end
    end
  end
end
