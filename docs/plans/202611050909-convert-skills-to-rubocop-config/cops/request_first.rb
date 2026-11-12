# frozen_string_literal: true

require 'rubocop'

module RuboCop
  module Cop
    module Planner
      # Flags examples that do not start with the request and a blank line (writing-rspec-controller-specs).
      class RequestFirst < Base
        MSG_FIRST = 'Make the request on the first line of the example.'
        MSG_BLANK_LINE = 'Follow the request with a blank line.'

        # @!method example_block?(node)
        def_node_matcher :example_block?, <<~PATTERN
          (block (send nil? {:it :specify :example} ...) ...)
        PATTERN

        def on_block(node)
          return unless example_block?(node)

          first, second = statements(node)
          return add_offense(node.send_node, message: MSG_FIRST) if first.nil?
          return add_offense(first, message: MSG_FIRST) unless request?(first)

          add_offense(first, message: MSG_BLANK_LINE) if second && second.first_line - first.last_line < 2
        end

        private

        def statements(node)
          body = node.body
          return [] if body.nil?

          body.begin_type? ? body.children : [body]
        end

        def request?(statement)
          statement.send_type? && statement.receiver.nil? && request_methods.include?(statement.method_name)
        end

        def request_methods
          @request_methods ||= cop_config.fetch('RequestMethods').map(&:to_sym)
        end
      end
    end
  end
end
