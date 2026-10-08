# frozen_string_literal: true

require 'application_system_test_case'
require 'base64'
require 'digest'
require 'json'

class SubmissionVersionsTest < ApplicationSystemTestCase
  include ActionMailer::TestHelper
  test 'staff reviews all submitted document types and downloads both immutable versions after replacement' do
    evidence_dir = Rails.root.join('tmp/snapshot-document-types-evidence')
    FileUtils.mkdir_p(evidence_dir)
    staff = FactoryGirl.create(:user, role: User::STAFF)
    thesis = FactoryGirl.create(:thesis, embargo_selection: :not_requested)
    thesis.loc_subjects << LocSubject.first
    original = Rails.root.join('test/fixtures/files/Tony_Rich_E_2012_Phd.pdf')
    replacement = evidence_dir.join('replacement.pdf')
    write_replacement_pdf(replacement)
    FileUtils.cp(original, evidence_dir.join('original.pdf'))
    original_hash = Digest::SHA256.file(original).hexdigest
    replacement_hash = Digest::SHA256.file(replacement).hexdigest
    assert_not_equal original_hash, replacement_hash

    primary = FactoryGirl.create(:document, thesis: thesis, user: thesis.student,
                                 usage: :thesis, supplemental: false,
                                 file: Rack::Test::UploadedFile.new(original, 'application/pdf'))
    Document.usages.each_key do |usage|
      document = FactoryGirl.create(:document, thesis: thesis, user: thesis.student, usage: usage,
                         supplemental: true,
                         file: Rack::Test::UploadedFile.new(replacement, 'application/pdf'))
      # Shared embargo numbering can change the factory uploader's name after reload.
      document.reload
      FileUtils.mkdir_p(File.dirname(document.file.path))
      FileUtils.cp(replacement, document.file.path) unless File.exist?(document.file.path)
    end
    thesis.documents.each { |document| assert File.file?(document.reload.file.path) }

    sign_in_for_browser(thesis.student)
    submit_thesis(thesis)
    assert_equal 1, thesis.submission_versions.count
    thesis.documents.each do |document|
      assert File.file?(document.reload.file.path), "Snapshot removed source document #{document.id}"
      expected = document.id == primary.id ? original_hash : replacement_hash
      assert_equal expected, Digest::SHA256.file(document.file.path).hexdigest
    end
    first_version = thesis.submission_versions.find_by!(version_number: 1)
    assert_equal Document.usages.keys.sort, first_version.submission_documents.pluck(:usage).uniq.sort
    assert_equal Document.usages.size + 1, first_version.submission_documents.count

    sign_in_for_browser(staff)
    visit student_thesis_path(thesis.student, thesis)
    assert_version_labels(1)

    ActionMailer::Base.deliveries.clear
    find('#status_menu .dropdown-toggle').click
    choose('status', option: Thesis::RETURNED)
    uncheck('notify_student')
    assert_not find('#notify_current_user').checked?
    assert_no_enqueued_emails do
      click_button('Change Status')
      assert_selector '#status_menu .badge', text: 'Returned'
    end
    assert_equal Thesis::RETURNED, thesis.reload.status
    assert_empty ActionMailer::Base.deliveries

    sign_in_for_browser(thesis.student)
    visit student_view_thesis_process_path(thesis, Thesis::PROCESS_UPLOAD)
    within("#document_#{primary.id}") { click_link('Replace') }
    attach_file('document_file', replacement)
    click_button('Upload')
    assert_selector '.alert-success', text: 'File uploaded.'
    assert_equal replacement_hash, Digest::SHA256.file(primary.reload.file.path).hexdigest
    assert_equal 1, thesis.submission_versions.count, 'Replacing a draft must not create a submitted version'

    submit_thesis(thesis)
    assert_equal 2, thesis.submission_versions.count
    sign_in_for_browser(staff)
    visit student_thesis_path(thesis.student, thesis)
    assert_version_labels(1)
    assert_version_labels(2)

    downloads = thesis.submission_versions.order(:version_number).map do |version|
      document = version.submission_documents.primary.first!
      href = student_thesis_submission_version_submission_document_path(thesis.student, thesis, version, document)
      response = download_through_browser(href)
      assert_nil response['error']
      assert_equal 200, response['status']
      assert_includes response['disposition'], 'attachment'
      downloaded_bytes = Base64.strict_decode64(response.fetch('base64'))
      downloaded_file = evidence_dir.join("downloaded-version-#{version.version_number}.pdf")
      File.binwrite(downloaded_file, downloaded_bytes)
      downloaded_hash = Digest::SHA256.hexdigest(downloaded_bytes)
      expected_hash = version.version_number == 1 ? original_hash : replacement_hash
      assert_equal expected_hash, downloaded_hash, "Version #{version.version_number} download changed"
      { version: version.version_number, path: href, status: response['status'],
        file: downloaded_file.basename.to_s, bytes: response['bytes'], expected_sha256: expected_hash, downloaded_sha256: downloaded_hash }
    end

    # A future or corrupt stored enum must not break access to the other preserved files.
    unknown = first_version.submission_documents.find_by!(usage: :modification_request)
    connection = ThesisSubmissionDocument.connection
    ThesisSubmissionDocument.where(id: unknown.id).update_all("#{connection.quote_column_name('usage')} = 999")
    assert_nil unknown.reload.usage
    visit student_thesis_path(thesis.student, thesis)
    within(version_section(1)) do
      assert_selector 'tr', text: /#{Regexp.escape(unknown.display_name)}.*Unknown/m
      assert_link 'Download', count: Document.usages.size + 1
    end
    File.write(evidence_dir.join('downloads.json'), JSON.pretty_generate(
      scenario: 'student submit, staff return without email, draft replace, student resubmit, staff downloads',
      usages: Document.usages.keys, original_sha256: original_hash, replacement_sha256: replacement_hash,
      versions_after_draft_replacement: 1, versions_after_resubmission: 2,
      return_notifications: 0, return_queued_emails: 0, unknown_label: 'Unknown', downloads: downloads
    ))
  end

  private

  def write_replacement_pdf(path)
    # A valid one-page PDF with visibly different content from the original thesis fixture.
    stream = "BT /F1 24 Tf 72 720 Td (Revised snapshot test PDF) Tj ET\n"
    objects = [
      '<< /Type /Catalog /Pages 2 0 R >>',
      '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
      "<< /Length #{stream.bytesize} >>\nstream\n#{stream}endstream"
    ]
    pdf = +"%PDF-1.4\n"
    offsets = objects.each_with_index.map do |object, index|
      offset = pdf.bytesize
      pdf << "#{index + 1} 0 obj\n#{object}\nendobj\n"
      offset
    end
    xref_offset = pdf.bytesize
    pdf << "xref\n0 6\n0000000000 65535 f \n"
    offsets.each { |offset| pdf << format("%010d 00000 n \n", offset) }
    pdf << "trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n#{xref_offset}\n%%EOF\n"
    File.binwrite(path, pdf)
  end

  def sign_in_for_browser(user)
    Capybara.reset_sessions!
    Warden.test_reset!
    login_as(user)
    visit login_path
  end

  def submit_thesis(thesis)
    visit student_view_thesis_process_path(thesis, Thesis::PROCESS_SUBMIT)
    check('I certify that the content is correct', allow_label_click: true)
    accept_confirm { click_button('I accept and submit for review') }
    assert_selector '.student-view.status h2', text: 'Thesis Submission Status'
    assert_selector '.student-view.status .text-bg-success', text: 'Under review'
    assert_equal Thesis::UNDER_REVIEW, thesis.reload.status
  end

  def version_section(number)
    find('.submission-versions h5', text: /\AVersion #{number}\b/).find(:xpath, '..')
  end

  def assert_version_labels(number)
    within(version_section(number)) do
      { 'Primary' => 1, 'Supplemental' => 1, 'Embargo' => 2,
        'Licence' => 1, 'Modification request' => 1 }.each do |label, count|
        assert_selector 'td:nth-child(2)', text: label, exact_text: true, count: count
      end
      assert_link 'Download', count: Document.usages.size + 1
    end
  end

  def download_through_browser(href)
    page.evaluate_async_script(<<~JAVASCRIPT, href)
      const done = arguments[arguments.length - 1];
      fetch(arguments[0], { credentials: 'same-origin' })
        .then(async response => {
          const bytes = new Uint8Array(await response.arrayBuffer());
          let binary = '';
          for (let offset = 0; offset < bytes.length; offset += 8192) {
            binary += String.fromCharCode(...bytes.subarray(offset, offset + 8192));
          }
          done({ status: response.status, disposition: response.headers.get('content-disposition'),
                 bytes: bytes.length, base64: btoa(binary) });
        }).catch(error => done({ error: error.message }));
    JAVASCRIPT
  end
end
