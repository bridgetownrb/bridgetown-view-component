module Bridgetown
  module ViewComponent
    class SanityCheckComponent < ::ViewComponent::Base
      include Bridgetown::ViewComponent

      def initialize(name:)
        @name = name
      end
    end
  end
end
