# frozen_string_literal: true

module Bridgetown
  module ViewComponentHelpers
    extend Forwardable

    def_delegators :@view_context, :liquid_render, :partial

    attr_reader :site # will be nil unless you explicitly set a `@site` ivar

    def self.helper_allow_list
      @helper_allow_list ||= %i(capture render t with_output_buffer)
    end

    def self.allow_rails_helpers(*helpers)
      helper_allow_list.concat(helpers)
    end

    def self.included(klass)
      helper_consts = ActionView::Helpers.constants.select do |c|
        ActionView::Helpers.const_get(c).is_a?(Module)
      end
      helper_consts.map { |c| ActionView::Helpers.const_get(c) }.each do |mod|
        (mod.public_instance_methods - Object.public_instance_methods).each do |method_name|
          klass.undef_method(method_name) unless helper_allow_list.include?(method_name)
        rescue NameError
          nil
        end
      end
    end

    def render(item, options = {}, &block)
      if item.respond_to?(:render_in)
        result = ""
        capture do # this ensures no leaky interactions between BT<=>VC blocks
          result = item.render_in(self, &block)
        end
        result&.html_safe
      else
        view_context.partial(item, options, &block)&.html_safe
      end
    end

    def helpers
      @helpers ||= Bridgetown::RubyTemplateView::Helpers.new(
        self, view_context&.site || Bridgetown::Current.site
      )
    end

    def method_missing(method, *args, **kwargs, &block)
      if helpers.respond_to?(method.to_sym)
        helpers.send method.to_sym, *args, **kwargs, &block
      else
        super
      end
    end

    def respond_to_missing?(method, include_private = false)
      helpers.respond_to?(method.to_sym, include_private) || super
    end
  end
end
