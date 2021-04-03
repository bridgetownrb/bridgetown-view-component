# frozen_string_literal: true

require "bridgetown-core"
require "action_view"
require "view_component"

# Create basic Rails namespace when in Bridgetown-only context
unless defined?(Rails)
  module Rails
    module UrlHelpers; end

    def self.version
      ActionView.version.to_s
    end

    def self.application
      @application ||= HashWithDotAccess::Hash.new({
        routes: { url_helpers: UrlHelpers }
      })
    end

    def self.env
      @env ||= HashWithDotAccess::Hash.new({ production?: Bridgetown.env.production? })
    end
  end

  unless Rails.version.to_f >= 6.1
    require "view_component/render_monkey_patch"
    ActionView::Base.prepend ViewComponent::RenderMonkeyPatch
  end
end

# Load classes/modules

module Bridgetown
  module ViewComponent
  end

  autoload :ViewComponentHelpers,
           "bridgetown-view-component/bridgetown/view_component_helpers"
  autoload :ComponentValidation,
           "bridgetown-view-component/bridgetown/component_validation"
end

# Set up the test components source manifest
Bridgetown::PluginManager.new_source_manifest(
  origin: Bridgetown::ViewComponent,
  components: File.expand_path("../components", __dir__)
)

# Add a few methods to Bridgetown's Ruby template superclasses
[Bridgetown::RubyTemplateView, Bridgetown::Component].each do |klass|
  klass.class_eval do
    def lookup_context
      HashWithDotAccess::Hash.new(variants: [])
    end

    def view_renderer
      nil
    end

    def view_flow
      nil
    end
  end
end
