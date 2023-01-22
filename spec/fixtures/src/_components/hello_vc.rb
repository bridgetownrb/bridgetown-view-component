class HelloVc < ViewComponent::Base
  Bridgetown::ViewComponentHelpers.allow_rails_helpers :tag
  include Bridgetown::ViewComponentHelpers

  renders_many :posts

  def initialize(name:)
    @name = name
  end
end