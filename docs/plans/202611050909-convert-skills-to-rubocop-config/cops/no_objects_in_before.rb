# frozen_string_literal: true

require 'rubocop'

module RuboCop
  module Cop
    module Planner
      # Flags objects created in `before` hooks (writing-rspec: set up objects with let, not before).
      class NoObjectsInBefore < Base
        MSG = 'Create objects with `let!` or `let`, not in `before`.'

        # @!method hook_block?(node)
        def_node_matcher :hook_block?, <<~PATTERN
          (block (send nil? {:before :prepend_before :append_before} ...) ...)
        PATTERN

        def on_block(node)
          return unless hook_block?(node)

          node.body&.each_node(:send) do |send_node|
            add_offense(send_node) if object_creation?(send_node) && !time_travel_argument?(send_node)
          end
        end

        private

        def object_creation?(send_node)
          receiver = send_node.receiver
          return creation_methods.include?(send_node.method_name) if receiver.nil?

          receiver.const_type? && constructor_methods.include?(send_node.method_name)
        end

        def time_travel_argument?(send_node)
          send_node.each_ancestor(:send).any? do |ancestor|
            ancestor.receiver.nil? && time_travel_methods.include?(ancestor.method_name)
          end
        end

        def creation_methods
          @creation_methods ||= cop_config.fetch('CreationMethods').map(&:to_sym)
        end

        def constructor_methods
          @constructor_methods ||= cop_config.fetch('ConstructorMethods').map(&:to_sym)
        end

        def time_travel_methods
          @time_travel_methods ||= cop_config.fetch('TimeTravelMethods').map(&:to_sym)
        end
      end
    end
  end
end
