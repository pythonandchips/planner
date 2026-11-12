# frozen_string_literal: true

require 'rubocop'

module RuboCop
  module Cop
    module Planner
      # Flags examples whose first expectation is not the status check (writing-rspec-controller-specs).
      class StatusCheckedFirst < Base
        MSG_FIRST = 'Make the first expectation `expect(response).to have_http_status(...)`.'
        MSG_BLANK_LINE = 'Follow the status check with a blank line.'

        # @!method example_block?(node)
        def_node_matcher :example_block?, <<~PATTERN
          (block (send nil? {:it :specify :example} ...) ...)
        PATTERN

        # @!method expectation?(node)
        def_node_matcher :expectation?, <<~PATTERN
          (send {(send nil? :expect ...) (block (send nil? :expect) ...) (send nil? :is_expected)}
            {:to :not_to :to_not} ...)
        PATTERN

        # @!method status_check?(node)
        def_node_matcher :status_check?, <<~PATTERN
          (send (send nil? :expect (send nil? :response)) :to (send nil? :have_http_status _))
        PATTERN

        def on_block(node)
          return unless example_block?(node)

          statements = statements(node)
          index = statements.index { |statement| expectation?(statement) }
          return add_offense(node.send_node, message: MSG_FIRST) if index.nil?

          check_status(statements[index], statements[index + 1])
        end

        private

        def check_status(check, following)
          return add_offense(check, message: MSG_FIRST) unless status_check?(check)

          add_offense(check, message: MSG_BLANK_LINE) if following && following.first_line - check.last_line < 2
        end

        def statements(node)
          body = node.body
          return [] if body.nil?

          body.begin_type? ? body.children : [body]
        end
      end
    end
  end
end
