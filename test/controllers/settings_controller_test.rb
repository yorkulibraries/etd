# frozen_string_literal: true

require 'test_helper'

class SettingsControllerTest < ActionController::TestCase
  setup do
    AppSettings.clear_cache
    log_user_in(create(:user, role: User::ADMIN))
  end

  should 'show the invitation validity setting with its default' do
    get :edit

    assert_response :success
    assert_select 'input#app_settings_invitation_validity_days[value="14"]'
  end

  should 'allow an admin to change invitation validity' do
    patch :update, params: { app_settings: { invitation_validity_days: '21' } }

    assert_equal 21, AppSettings.invitation_validity_days
    assert_redirected_to edit_settings_path
  end

  should 'reject an invalid invitation validity without changing the setting' do
    AppSettings.invitation_validity_days = 14

    patch :update, params: { app_settings: { invitation_validity_days: '0' } }

    assert_equal 14, AppSettings.invitation_validity_days
    assert_equal 'Invitation validity must be a positive number of calendar days.', flash[:alert]
    assert_redirected_to edit_settings_path
  end

  should 'not allow staff to manage settings' do
    log_user_in(create(:user, role: User::STAFF))

    get :edit

    assert_redirected_to unauthorized_path
  end
end
