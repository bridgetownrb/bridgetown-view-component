# frozen_string_literal: true

module Bridgetown
  module ComponentValidation
    def self.included(klass)
      klass.attr_reader :frontmatter
    end

    def frontmatter=(yaml_data)
      @frontmatter = yaml_data.with_dot_access

      frontmatter.validate&.each do |variable, type|
        unless send(variable).is_a?(Kernel.const_get(type))
          raise "Validation error while rendering #{self.class}: " \
                "`#{variable}' is not of type `#{type}'"
        end
      end
    end
  end
end
