# frozen_string_literal: true

module Bridgetown
  module ViewComponentHelpers
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

    def helpers
      @helpers ||= Bridgetown::RubyTemplateView::Helpers.new(self, @view_context.site)
    end

    def method_missing(method, *args, &block)
      if helpers.respond_to?(method.to_sym)
        helpers.send method.to_sym, *args, &block
      else
        super
      end
    end

    def respond_to_missing?(method, include_private = false)
      helpers.respond_to?(method.to_sym, include_private) || super
    end
  end
end
