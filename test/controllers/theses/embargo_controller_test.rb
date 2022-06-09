require 'test_helper'

class Theses::EmbargoControllerTest < ActionController::TestCase

  setup do
    @user = create(:user, role: User::ADMIN)
    @student = create(:student)
    @thesis = create(:thesis, student: @student)
    log_user_in(@user)
  end

  should "set thesis for permantent embargo" do
    post :create, params: { student_id: @student, thesis_id: @thesis, thesis: { embargo: "Test" } }

    thesis = assigns(:thesis)

    assert thesis.embargoed == true, "Embargoed should be set to true"
    assert_not_nil thesis.embargoed_at, "Datetime record"
    assert thesis.embargoed_by_id == @user.id, "User ID should be recorded"

    assert thesis.published_at > 499.years.from_now, "Should be at least 499 years in the future"

    assert_redirected_to student_thesis_path(@student, @thesis)
  end

end
