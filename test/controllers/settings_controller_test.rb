# frozen_string_literal: true

require 'test_helper'

class SettingsControllerTest < ActionController::TestCase
  context 'as an administrator' do
    setup do
      @user = create(:user, role: User::ADMIN)
      log_user_in(@user)
    end

    should 'render the general settings form' do
      get :edit

      assert_response :success
      assert_template :edit
    end

    should 'render the DSpace settings form' do
      get :dspace

      assert_response :success
      assert_template :dspace
    end

    should 'persist settings and return to the general settings page by default' do
      patch :update, params: { app_settings: { app_name: 'ETD Test' } }

      assert_equal 'ETD Test', AppSettings.app_name
      assert_redirected_to edit_settings_path
    end

    should 'persist DSpace settings and show a confirmation' do
      patch :update, params: {
        app_settings: { dspace_live_username: 'exporter@example.com' },
        return_to: 'dspace'
      }

      assert_equal 'exporter@example.com', AppSettings.dspace_live_username
      assert_redirected_to dspace_settings_path
      assert_equal 'Saved DSpace Settings', flash[:notice]
    end
  end

  should 'deny settings access to students' do
    student = create(:student)
    log_user_in(student)

    get :edit

    assert_redirected_to unauthorized_url
  end
end
