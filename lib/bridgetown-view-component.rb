# frozen_string_literal: true

require "bridgetown-core"
require "action_view"
require "view_component"
require "view_component/compile_cache"

# Create basic Rails namespace when in Bridgetown-only context
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

# Load classes/modules

require "bridgetown-view-component/bridgetown/view_component"

module Bridgetown
  autoload :ViewComponentHelpers,
           "bridgetown-view-component/bridgetown/view_component_helpers"
  autoload :CapturingViewComponent,
           "bridgetown-view-component/bridgetown/capturing_view_component"
  autoload :SerbeaCapturingViewComponent,
           "bridgetown-view-component/bridgetown/capturing_view_component"
  autoload :ComponentValidation,
           "bridgetown-view-component/bridgetown/component_validation"
end

# Set up the test components source manifest
Bridgetown::PluginManager.new_source_manifest(
  origin: Bridgetown::ViewComponent,
  components: File.expand_path("../components", __dir__)
)

# Add a few methods to Bridgetown's Ruby template superclass
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

# Hack needed until ViewComponent allows for a customizable @output_buffer class
module ViewComponent
  class BridgetownCompiler < Compiler
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Lint/UselessAssignment
    def compile(raise_errors: false)
      return if compiled?

      if template_errors.present?
        raise ViewComponent::TemplateError, template_errors if raise_errors

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
        provided_collection_parameter || name.demodulize.underscore.chomp("_component").to_sym
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
        if component_class.instance_methods.include?(method_name.to_sym)
          component_class.send(:undef_method, method_name.to_sym)
        end

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
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Lint/UselessAssignment
  end
end
