# frozen_string_literal: true

require 'test_helper'

class ChosenBootstrapThemeAssetTest < ActiveSupport::TestCase
  should 'compile the vendored chosen bootstrap theme into application.css' do
    asset = Rails.application.assets.find_asset('application.css')

    assert asset, 'application.css should be on the asset path'
    assert_includes asset.to_s, '.chosen-container.chosen-container-single'
  end
end
