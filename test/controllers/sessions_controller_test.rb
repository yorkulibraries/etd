require 'test_helper'

class SessionsControllerTest < ActionController::TestCase
  should 'create a new session information if user logs in' do
    user = create(:user, username: 'test')
    @request.env['HTTP_PYORK_USER'] = user.username

    get :new

    assert_equal user.id, session[:user_id]
    assert_redirected_to root_url
    assert_equal 'Logged in!', flash[:notice]
  end

  should "redirect to student path if CYIN is provided and YORK_USER doesn't match" do
    student = create(:student, sisid: '123123123')
    @request.env['HTTP_PYORK_USER'] = 'something'
    @request.env['HTTP_PYORK_CYIN'] = student.sisid

    get :new

    assert_equal student.id, session[:user_id]
    assert_redirected_to student_view_index_url
  end

  should 'test redirection to a student Path if the user is logged in' do
    student = create(:student, sisid: '123123123')
    # @request.env["HTTP_PYORK_TYPE"] = Student::ALLOWED_TYPE
    @request.env['HTTP_PYORK_CYIN'] = student.sisid

    get :new

    assert_equal student.id, session[:user_id]
    assert_redirected_to student_view_index_url
  end

  should "save student username if it's a student and username is not set" do
    student = create(:student, username: '123123123', sisid: '123123123')

    @request.env['HTTP_PYORK_TYPE'] = Student::ALLOWED_TYPE
    @request.env['HTTP_PYORK_CYIN'] = student.sisid
    @request.env['HTTP_PYORK_USER'] = 'student_user'

    get :new

    assert_equal student.id, session[:user_id]
    student.reload
    assert_equal 'student_user', student.username, 'Student username was saved'
    assert_redirected_to student_view_index_url
  end

  should 'reject usersession if User is not in the system' do
    @request.env['HTTP_PYORK_USER'] = 'invalid_user_name'

    get :new
    assert_redirected_to invalid_login_url, 'Shold redirect to invalid login url'
  end

  should 'destroy session information when logout is present' do
    get :destroy

    assert_equal nil, session[:user_id]
    assert_redirected_to 'http://www.library.yorku.ca'
  end
end
