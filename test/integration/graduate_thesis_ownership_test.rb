# frozen_string_literal: true

# Written before the ownership correction: nested contact updates must not
# accept a foreign student, a mismatched thesis ID, or a closed thesis. Own open
# records must remain usable through both Passport York and linked sign-in.
require 'test_helper'
require_relative '../support/graduate_oauth_flow'

class GraduateThesisOwnershipTest < ActionDispatch::IntegrationTest
  include GraduateOAuthFlow

  setup do
    host! '127.0.0.1:3210'
    @student = create(:student)
    @thesis = create(:thesis, student: @student)
    @other = create(:student, name: 'Foreign Contact Owner')
    @foreign_thesis = create(:thesis, student: @other)
    @forgery = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    OmniAuth.config.test_mode = true
    mock_provider
    ppy_login(@student)
    complete_oauth
    fresh_browser
    complete_oauth
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @forgery
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.clear
    Warden.test_reset!
  end

  test 'foreign parent cannot be used to update another student' do
    update_contact(@other, @foreign_thesis)
    assert_redirected_to unauthorized_path
    assert_equal 'Foreign Contact Owner', @other.reload.name
  end

  test 'own parent cannot be combined with another students thesis' do
    assert_raises(ActiveRecord::RecordNotFound) { update_contact(@student, @foreign_thesis) }
    assert_equal 'Foreign Contact Owner', @other.reload.name
  end

  test 'closed own thesis does not bypass the existing edit restriction' do
    original_name = @student.name
    @thesis.update!(status: Thesis::PUBLISHED)
    update_contact(@student, @thesis)
    assert_redirected_to unauthorized_path
    assert_equal original_name, @student.reload.name
  end

  test 'own open contact update still works through both sign in methods' do
    update_contact(@student, @thesis)
    assert_redirected_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_UPDATE)
    assert_equal 'Authorized Contact Update', @student.reload.name
    fresh_browser
    ppy_login(@student)
    update_contact(@student, @thesis)
    assert_redirected_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_UPDATE)
  end

  private

  def update_contact(student, thesis)
    get graduate_login_path
    post organize_student_information_student_thesis_path(student, thesis), params: {
      authenticity_token: csrf_token,
      student: { name: 'Authorized Contact Update', first_name: 'Authorized', email_external: 'verified@example.com' }
    }
  end
end
