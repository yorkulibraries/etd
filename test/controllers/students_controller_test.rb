# frozen_string_literal: true

require 'test_helper'

class StudentsControllerTest < ActionController::TestCase
  should 'not be visible unless logged in' do
    get :index
    assert_redirected_to login_path
  end

  context 'as admin' do
    setup do
      @user = create(:user, role: User::ADMIN)
      log_user_in(@user)
    end

    should 'list all students' do
      create_list(:student, 5, blocked: false)
      create_list(:student, 2, blocked: true)

      get :index
      students = assigns(:students)

      assert students, "Students can't be nil"
      assert_equal 7, students.count, 'There should be 5 students'
    end

    should 'show a new student form when seeing new, role select should not be present, sisid should' do
      get :new

      student = assigns(:student)
      assert student, "Student can't be nil"
      assert_nil student.id, 'ID should not be set'

      assert_select 'form#new_student', 1, 'An HTML Form should be present'
      assert_select 'select#student_role', 0, 'Role select dropdown should not be there'
    end

    should 'create a new Student and set the role by default to be User::STUDENT' do
      student_attrs = attributes_for(:student, role: User::MANAGER)

      assert_difference 'Student.count', 1 do
        post :create, params: { student: student_attrs.except(:created_by_id, :blocked, :role) }
      end
      student = assigns(:student)
      assert student, 'Student object was assigned'
      assert_equal @user.id, student.created_by.id, 'user created by should be as the current user'
      assert_equal User::STUDENT, student.role, "user role should be #{User::STUDENT}"

      assert_redirected_to student_path(student)
    end

    should 'Create the record automatically if from GemRecord and brand new student, make sure student is blocked by default.' do
      create(:gem_record, sisid: '111111112', studentname: 'joe smith', emailaddress: 'test@email.com')

      assert_difference 'Student.count', 1 do
        get :new, params: { sisid: '111111112' }
      end

      student = assigns(:student)
      assert_redirected_to student_path(student)

      assert student, 'Created an new student'
      assert_equal '111111112', student.username, 'By default username should be prepopulated with sisid.'
      assert_equal 'joe smith', student.name, 'Make sure student name matches'
      assert_equal '111111112', student.sisid.to_s, 'Sisid should match'
      assert_equal 'test@email.com', student.email, 'Emails should match'
      assert_equal @user.id, student.created_by.id, 'Make sure created by is assigned'
      assert_equal User::STUDENT, student.role, 'Role should be student'
      assert_equal true, student.blocked, 'SHOULD BE BLOCKED BY DEFAULT'
    end

    should "not create a new student automatically if sisid is passed and GemRecord doesn't exist" do
      assert_no_difference 'Student.count' do
        get :new, params: { sisid: '2323232323' }
      end
    end

    should 'not create a new student from gem record if the student exists already' do
      create(:gem_record, sisid: '111222333')
      create(:student, sisid: '111222333')

      assert_no_difference 'Student.count' do
        get :new, params: { sisid: '111222333' }
      end

      assert_template 'new'
    end

    should 'set created_by after the user is created' do
      student_attrs = attributes_for(:student)

      post :create, params: { student: student_attrs.except(:created_by_id, :blocked, :role) }

      student = assigns(:student)
      assert student, 'Student cant be nil'
      assert_equal @user.id, student.created_by.id, 'Current @user should be set as teh creator'
    end

    should 'show details page with student info' do
      s = create(:student)
      create(:gem_record, sisid: s.sisid, seqgradevent: 1)

      get :show, params: { id: s.id }

      student = assigns(:student)
      available_theses = assigns(:available_theses)

      assert student, 'Student must be an object'
      assert_equal s.id, student.id, 'Ids should match'
      assert_equal 1, available_theses.count, 'Must have one available thesis'
    end

    should 'load current, available, and completed theses and display them' do
      s = create(:student)

      create(:gem_record, sisid: s.sisid, examresult: GemRecord::ACCEPTED, seqgradevent: 1)
      create(:gem_record, sisid: s.sisid, examresult: GemRecord::ACCEPTED, seqgradevent: 2)
      create(:gem_record, sisid: s.sisid, examresult: GemRecord::ACCEPTED, seqgradevent: 3)

      create(:thesis, student: s, status: Thesis::OPEN, gem_record_event_id: 1)
      create(:thesis, student: s, status: Thesis::ACCEPTED, gem_record_event_id: 2)

      get :show, params: { id: s.id }

      current_theses = assigns(:current_theses)
      available_theses = assigns(:available_theses)

      assert assigns(:current_theses)
      assert assigns(:available_theses)

      assert_equal 2, current_theses.size, 'There are two current theses'
      assert_equal 1, available_theses.size, 'There is one gem record'
    end

    should 'show edit page' do
      s = create(:student)

      get :edit, params: { id: s.id }

      student = assigns(:student)
      assert student, "Student can't be nil"
      assert_equal s.id, student.id, 'Ids should match'

      assert_select "form#edit_student_#{s.id}", 1, ' An HTML Form should be present'
    end

    should 'update existing student, role should be immutable' do
      s = create(:student, username: 'test', name: 'whatever')

      post :update, params: { id: s.id, student: { username: 'test2', name: 'whatever2', role: User::ADMIN } }

      student = assigns(:student)
      assert student, "Student can't be nil"
      assert_equal 'test2', student.username, 'Student username should have changed'
      assert_equal 'whatever2', student.name, 'Student name should have changed'
      assert_equal User::STUDENT, student.role, "Student role shouldn't have changed"

      assert_redirected_to student_path(student), 'Should redirect to student details page'
    end

    should 'be able to block students' do
      student = create(:student)

      assert_no_difference 'Student.count' do
        post :block, params: { id: student.id }
      end

      s = Student.find(student.id)
      assert s.blocked?, 'Student should be blocked'

      assert_redirected_to student_path(student), 'Should redirect to the student details'
    end

    should 'be able to unblock students' do
      student = create(:student, blocked: true)

      post :unblock, params: { id: student.id }

      assert_redirected_to student_path(student), 'Should redirect back to student details'
      assert_select 'div#student_blocked_message', 0, 'Should not display student blocked message'
    end

    #### GEM and SIS Search ####
    should 'search by student sisid, if found in db redirect to student, if not found redirect to the gem record' do
      gem_record = create(:gem_record, sisid: '202202202')
      create(:student, sisid: '111111111')

      post :gem_search, params: { sisid: '202202202' }

      assert_redirected_to gem_record_path(gem_record), 'Student is not in the database but is in GemRecords'

      post :gem_search, params: { sisid: '111111111' }
      s = assigns(:student)
      assert_redirected_to student_path(s), 'Should redirect to student details, since student is already registerd.'
    end

    should 'Should redirect to Gem Records with a message that student is not allowed to be added if there is no corresponding GemRecord' do
      post :gem_search, params: { sisid: '333333333' }

      assert_redirected_to gem_records_path
      assert_equal 'Student was not found.', flash[:alert]
    end

    ### SHOULD FIND STUDENTS BASED ON NAME OR SISID ###
    should 'find students based on SISID or NAME, working for both gem record or regular student. if multiple, redirect to index of either models' do
      # search for existing John
      post :gem_search, params: { sisid: 'Johnx' }
      students = assigns(:students)
      assert_equal 0, students.size, 'Number of students matching Johnx'

      create(:gem_record, sisid: '222222222', studentname: 'Jeremy Smith')
      create(:gem_record, sisid: '333333333', studentname: 'Jeremy Clarkson')

      # create some new students
      create(:student, sisid: '111111111', name: 'Johnx Smith')
      students = assigns(:students)
      assert_equal 1, students.size, 'Number of students matching Johnx'

      create(:student, sisid: '444444444', name: 'Johnx Clarkson')
      students = assigns(:students)
      assert_equal 2, students.size, 'Number of students matching Johnx'
      
      # search name of student
      post :gem_search, params: { sisid: 'Johnx' }
      assert assigns(:search_result), 'Indicate that this is a search result'
      students = assigns(:students)
      assert_equal 2, students.size, 'Number of students matching Johnx'

      assert_template 'students/index'

      # search sisid
      post :gem_search, params: { sisid: '111111111' }
      student = assigns(:student)
      assert_redirected_to student_path(student), 'Redirects to student record'

      # search name in gem record
      post :gem_search, params: { sisid: 'Jeremy' }
      assert assigns(:search_result), 'Indicate that this is a search result'
      gem_records = assigns(:gem_records)
      assert_equal 2, gem_records.size, 'Found two Jeremys'
      assert_template 'gem_records/index'

      post :gem_search, params: { sisid: '222222222' }
      gem_record = assigns(:gem_record)
      assert_redirected_to gem_record_path(gem_record), 'Redirects to gem record '
    end

    ### PAGINATION TESTS ###

    should 'paginate students, 25 at a time' do
      create_list(:student, 40)

      get :index, params: { page: 1 }

      students = assigns(:students)
      assert_equal 25, students.count, 'first page, 25'

      get :index, params: { page: 2 }

      students = assigns(:students)
      assert_equal 15, students.count, 'second page, 15'
    end

    should 'display audit trail for this student, including theses and documents' do
      student = create(:student)
      create(:thesis, student:)

      get :audit_trail, params: { id: student.id }

      assert assigns(:audits)
      assert assigns(:audits_grouped)
    end

    should 'send an invitation email' do
      student = create(:student)
      create(:thesis, student:)

      get :send_invite, params: { id: student.id }

      s = assigns(:student)
      assert_equal "Sent an invitation email to #{student.name}.", flash[:notice]
      assert_not_nil s.invitation_sent_at, 'Should set the inviation sent at date'
      assert_redirected_to student_path(student)
    end

    should 'not remove student if current user is not a manager' do
      student = create(:student)

      assert_no_difference 'Student.count' do
        post :destroy, params: { id: student.id }
      end
    end
  end

  context 'as a manager' do
    setup do
      @user = create(:user, role: User::MANAGER)
      log_user_in(@user)
    end

    should 'remove student completly if current user is manager' do
      student = create(:student)
      thesis = create(:thesis, student:)
      create(:document, thesis:)

      assert_difference ['Student.count', 'Thesis.count', 'Document.count'], -1 do
        post :destroy, params: { id: student.id }
      end
    end
  end

  context 'as student' do
    setup do
      @student = create(:student)
      @thesis = create(:thesis, student: @student)
      log_user_in(@student)
    end

    should 'see student detials of himself' do
      ability = Ability.new(@student)
      assert ability.can?(:show, Student)
    end

    should 'not be able to anything else or see other students' do
      ability = Ability.new(@student)
      assert ability.cannot?(:create, Student)
      assert ability.cannot?(:new, Student)
      assert ability.cannot?(:destroy, Student)
      assert ability.cannot?(:edit, Student)
      assert ability.cannot?(:update, Student)
    end

    should 'redirect to student_view when Student#show action is called' do
      get :show, params: { id: @student.id }

      assert_redirected_to student_view_index_path, 'Should redirect there'
    end
  end
end
