# frozen_string_literal: true

module Bridgetown
  module ViewComponent
    # NOTE: Currently not in use...might need to revisit when dual Rails/Bridgetown
    # installs are present
    def self.setup_hooks
      Bridgetown::Hooks.register :site, :pre_render, reloadable: false do
        ::ViewComponent::CompileCache.cache.each do |component_class|
          component_class.undef_method(:call)
        end
        ::ViewComponent::CompileCache.cache.clear
      end

      Bridgetown::Hooks.register :site, :post_render, reloadable: false do |_post|
        ::ViewComponent::CompileCache.cache.each do |component_class|
          component_class.undef_method(:call)
        end
        ::ViewComponent::CompileCache.cache.clear
      end
    end

    def self.included(klass)
      klass.extend ClassMethods
    end

    module ClassMethods
      def content_format(type)
        @content_format = type
      end

      def format_for_content
        @content_format ||= :default
      end
    end

    def content
      if self.class.format_for_content == :markdown && view_context.respond_to?(:markdownify)
        view_context.markdownify(@content).html_safe
      else
        super
      end
    end

    def render_in(view_context, &block)
      if view_context.class.name&.start_with? "Bridgetown"
        singleton_class.include ViewComponentHelpers

        ::ViewComponent::BridgetownCompiler.new(self.class).compile(raise_errors: true)
      end

      super
    end
  end
end
