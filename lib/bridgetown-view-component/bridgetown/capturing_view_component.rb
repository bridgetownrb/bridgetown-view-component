# frozen_string_literal: true

module Bridgetown
  class CapturingViewComponent < ::ViewComponent::Base
    include Bridgetown::ViewComponent

    def initialize(*args, &block)
      @_captured_args = args
      @_captured_block = block
    end

    def call
      @_erbout = Bridgetown::ERBBuffer.new
      value = nil
      buffer = with_output_buffer { value = instance_exec(*@_captured_args, &@_captured_block) }
      if (string = buffer.presence || value) && string.is_a?(String)
        string
      end
    end

    def method_missing(method, *args, &block)
      if view_context.respond_to?(method.to_sym)
        view_context.send method.to_sym, *args, &block
      else
        super
      end
    end

    def respond_to_missing?(method, include_private = false)
      view_context.respond_to?(method.to_sym, include_private) || super
    end
  end

  if defined?(Serbea)
    class SerbeaCapturingViewComponent < CapturingViewComponent
      alias_method :_erb_capture, :capture
      include Serbea::Helpers
      alias_method :capture, :_erb_capture
    end
  end
end
