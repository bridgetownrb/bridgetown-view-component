# frozen_string_literal: true

require "bridgetown-core"
require "action_view"
require "view_component"
require "view_component/compile_cache"

unless defined?(Rails)
  module Rails
    def self.version
      ActionView.version.to_s
    end

    def self.application
      nil
    end
  end

  unless Rails.version.to_f >= 6.1
    require "view_component/render_monkey_patch"
    ActionView::Base.prepend ViewComponent::RenderMonkeyPatch
  end
end

module Bridgetown
  module ViewComponent
    def self.setup_hooks
      Bridgetown::Hooks.register :site, :pre_rendera, reloadable: false do
        ::ViewComponent::CompileCache.cache.each do |component_class|
          component_class.undef_method(:call)
        end
        ::ViewComponent::CompileCache.cache.clear
      end
  
      Bridgetown::Hooks.register :site, :post_rendera, reloadable: false do |post|
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

  module ViewComponentHelpers
    def self.helper_allow_list
      @helper_allow_list ||= [:with_output_buffer]
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

      klass.delegate :partial, to: :view_context
      klass.delegate :render, to: :view_context
      klass.delegate :capture, to: :view_context
      klass.delegate :markdownify, to: :view_context
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

Bridgetown::PluginManager.new_source_manifest(
  origin: Bridgetown::ViewComponent,
  components: File.expand_path("../components", __dir__)
)

Bridgetown::ViewComponent.setup_hooks

module Bridgetown
  module ComponentValidation
    def self.included(klass)
      klass.attr_reader :frontmatter
    end

    def frontmatter=(yaml_data)
      @frontmatter = yaml_data.with_dot_access
  
      if frontmatter.validate
        frontmatter.validate.each do |variable, type|
          unless send(variable).is_a?(Kernel.const_get(type))
            raise "Validation error while rendering #{self.class}: `#{variable}' is not of type `#{type}'"
          end
        end
      end
    end
  end

  class CapturingViewComponent < ::ViewComponent::Base
    include Bridgetown::ViewComponent
  
    def initialize(*args, &block)
      @_captured_args = args
      @_captured_block = block
    end
  
    def call
      @_erbout = Bridgetown::ERBBuffer.new
      value = nil
      buffer = with_output_buffer { value = self.instance_exec(*@_captured_args, &@_captured_block) }
      if (string = buffer.presence || value) && string.is_a?(String)
        string
      end
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

Bridgetown::RubyTemplateView.class_eval do
  def lookup_context
    HashWithDotAccess::Hash.new(variants: [])
  end

  def view_renderer
    nil
  end

  def view_flow
    nil
  end

  def capture_in_view_component(*args, &block)
    capturing_component = if defined?(Serbea)
      Bridgetown::SerbeaCapturingViewComponent.new(*args, &block)
    else
      Bridgetown::CapturingViewComponent.new(*args, &block)
    end
    
    capturing_component.render_in(self)&.html_safe
  end
end

module ViewComponent
  class BridgetownCompiler < Compiler
    def compile(raise_errors: false)
      return if compiled?

      if template_errors.present?
        raise ViewComponent::TemplateError.new(template_errors) if raise_errors
        return false
      end

      if component_class.instance_methods(false).include?(:before_render_check)
        ActiveSupport::Deprecation.warn(
          "`before_render_check` will be removed in v3.0.0. Use `before_render` instead."
        )
      end

      # Remove any existing singleton methods,
      # as Ruby warns when redefining a method.
      component_class.remove_possible_singleton_method(:collection_parameter)
      component_class.remove_possible_singleton_method(:collection_counter_parameter)
      component_class.remove_possible_singleton_method(:counter_argument_present?)

      component_class.define_singleton_method(:collection_parameter) do
        if provided_collection_parameter
          provided_collection_parameter
        else
          name.demodulize.underscore.chomp("_component").to_sym
        end
      end

      component_class.define_singleton_method(:collection_counter_parameter) do
        "#{collection_parameter}_counter".to_sym
      end

      component_class.define_singleton_method(:counter_argument_present?) do
        instance_method(:initialize).parameters.map(&:second).include?(collection_counter_parameter)
      end

      component_class.validate_collection_parameter! if raise_errors

      methods_to_undef = []
      templates.each do |template|
        # Remove existing compiled template methods,
        # as Ruby warns when redefining a method.
        method_name = call_method_name(template[:variant])
        component_class.send(:undef_method, method_name.to_sym) if component_class.instance_methods.include?(method_name.to_sym)

        component_class.class_eval <<-RUBY, template[:path], -1
          def #{method_name}
            @output_buffer = Bridgetown::ERBBuffer.new
            #{compiled_template(template[:path])}
          end
        RUBY
      end

      define_render_template_for

      CompileCache.register(component_class)
    end
  end
end
