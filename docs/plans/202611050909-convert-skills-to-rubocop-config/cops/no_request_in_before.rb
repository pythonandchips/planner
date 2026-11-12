# frozen_string_literal: true

require 'rubocop'

module RuboCop
  module Cop
    module Planner
      # Flags requests made in `before` hooks (writing-rspec-controller-specs: the request belongs in the example).
      class NoRequestInBefore < Base
        MSG = 'Make the request in the example, not in `before`.'

        # @!method hook_block?(node)
        def_node_matcher :hook_block?, <<~PATTERN
          (block (send nil? {:before :prepend_before :append_before} ...) ...)
        PATTERN

        def on_block(node)
          return unless hook_block?(node)

          node.body&.each_node(:send) do |send_node|
            add_offense(send_node) if request?(send_node)
          end
        end

        private

        def request?(send_node)
          send_node.receiver.nil? && request_methods.include?(send_node.method_name)
        end

        def request_methods
          @request_methods ||= cop_config.fetch('RequestMethods').map(&:to_sym)
        end
      end
    end
  end
end
