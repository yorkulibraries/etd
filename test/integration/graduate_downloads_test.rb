# frozen_string_literal: true

require 'test_helper'
require_relative '../support/graduate_oauth_flow'
require 'fileutils'

class GraduateDownloadsTest < ActionDispatch::IntegrationTest
  include GraduateOAuthFlow

  setup do
    host! '127.0.0.1:3210'
    @student = create(:student)
    @thesis = create(:thesis, student: @student)
    @document = create(:document, thesis: @thesis, user: @student, supplemental: false,
                       file: Rack::Test::UploadedFile.new('test/fixtures/files/pdf-document.pdf', 'application/pdf'))
    @upload_directory = File.dirname(@document.file.path)
    @expected = File.binread(@document.file.path)
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
    FileUtils.rm_rf(@upload_directory) if @upload_directory
    ActionController::Base.allow_forgery_protection = @forgery
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.clear
    Warden.test_reset!
  end

  test 'external owner downloads exact bytes and view uses authorized link' do
    get download_student_thesis_document_path(@student, @thesis, @document)
    assert_response :success
    assert_equal @expected, response.body.b
    assert_includes response.headers['Content-Disposition'], 'attachment'
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_equal 'nosniff', response.headers['X-Content-Type-Options']
    get student_view_thesis_process_path(@thesis, Thesis::PROCESS_UPLOAD)
    assert_response :success
    assert_select "a[href='#{download_student_thesis_document_path(@student, @thesis, @document)}']", text: /Download/
    assert_not_includes response.body, @document.file_url
  end

  test 'closed thesis download remains allowed while edit remains denied and staff can read' do
    @thesis.update!(status: Thesis::PUBLISHED)
    get download_student_thesis_document_path(@student, @thesis, @document)
    assert_response :success
    assert_equal @expected, response.body.b
    get edit_student_thesis_document_path(@student, @thesis, @document)
    assert_redirected_to unauthorized_path
    ppy_login(create(:user))
    get download_student_thesis_document_path(@student, @thesis, @document)
    assert_response :success
    assert_equal @expected, response.body.b
  end

  test 'anonymous other student mismatched parents and blocked sessions cannot read file' do
    fresh_browser
    get download_student_thesis_document_path(@student, @thesis, @document)
    assert_redirected_to login_path
    other = create(:student)
    ppy_login(other)
    get download_student_thesis_document_path(@student, @thesis, @document)
    assert_redirected_to unauthorized_path
    assert_raises(ActiveRecord::RecordNotFound) do
      get download_student_thesis_document_path(other, @thesis, @document)
    end
    ppy_login(@student)
    @student.update!(blocked: true)
    get download_student_thesis_document_path(@student, @thesis, @document)
    assert_redirected_to login_path
  end

  test 'deleted and missing files return controlled not found' do
    @document.update_columns(deleted: true)
    get download_student_thesis_document_path(@student, @thesis, @document)
    assert_response :not_found
    @document.update_columns(deleted: false)
    File.unlink(@document.file.path)
    get download_student_thesis_document_path(@student, @thesis, @document)
    assert_response :not_found
    assert_not_includes response.body, @upload_directory
  end

  test 'symlink escaping document directory cannot return a local file' do
    outside = Rails.root.join('tmp/graduate-authentication/download-outside.txt')
    File.write(outside, 'private outside file')
    File.unlink(@document.file.path)
    File.symlink(outside, @document.file.path)
    get download_student_thesis_document_path(@student, @thesis, @document)
    assert_response :not_found
    assert_not_includes response.body, 'private outside file'
  ensure
    FileUtils.rm_f(outside) if outside
  end

  test 'real static boundary blocks raw uploads including encoded and dot segment variants' do
    fresh_browser
    raw = @document.file_url
    [raw, raw.sub('/uploads', '/%75ploads'), '/assets/..' + raw, '/' + raw,
     raw.sub('/uploads', '/%2fuploads'), raw.sub('/uploads', '/UPloads')].each do |url|
      get url
      assert_response :not_found, "Raw upload exposed: #{url}"
      assert_not_equal @expected, response.body.b
    end
    ppy_login(@student)
    get raw
    assert_response :not_found
  end
end
