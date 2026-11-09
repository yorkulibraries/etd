# frozen_string_literal: true

require 'test_helper'
require 'rake'
require 'etd/dspace_deposit_package'

extend Rake::DSL

# Loading the task file twice would make dspace:export run twice in other tests.
load Rails.root.join('lib/tasks/dspace_exporter.rake').to_s unless Rake::Task.task_defined?('dspace:export')
Rake::Task.define_task(:environment) unless Rake::Task.task_defined?(:environment)

# How the shared YorkSpace deposit package can go wrong, written before the code:
# 1. Two supervisors typed as "A / B" reach YorkSpace as one combined name.
# 2. A missing supervisor, abstract or exam date crashes the deposit instead of leaving the field out.
# 3. Hidden control characters in an abstract reach YorkSpace (they break the SWORD XML),
#    or removing them also removes real line breaks, paragraphs or tabs.
# 4. One copyright date field is missing, so YorkSpace records differ by deposit route.
# 5. A degree code stored in a different letter case gets no full degree name.
# 6. Supplemental files are sent before the main thesis file, or "main file only" still sends them.
# 7. Licence forms, embargo evidence, request-bound or modification files are sent to YorkSpace.
# 8. The website and the server script drift apart and send different records or files for one thesis.
class DspaceDepositPackageTest < ActiveSupport::TestCase
  Package = ETD::DspaceDepositPackage

  should 'send each supervisor as a separate name' do
    thesis = build(:thesis, supervisor: 'Ada Lovelace /  Alan Turing/ ')

    assert_equal ['Ada Lovelace', 'Alan Turing'], values(Package.entry(thesis), 'supervisor')
  end

  should 'leave out missing supervisor, abstract and exam date instead of crashing' do
    thesis = build(:thesis, supervisor: nil, abstract: nil, exam_date: nil)

    entry = Package.entry(thesis)

    assert_empty values(entry, 'supervisor')
    assert_empty values(entry, 'abstract')
    assert_empty values(entry, 'dateCopyrighted')
    assert_empty values(entry, 'date.copyright')
    assert_equal [thesis.title], values(entry, 'title')
  end

  should 'strip hidden control characters but keep line breaks, paragraphs and tabs' do
    thesis = build(:thesis, abstract: "One\u0002 line\nwrap.\n\n\tTwo\u000B\u000C\u000E\u000F end.")

    assert_equal ["One line\nwrap.\n\n\tTwo end."], values(Package.entry(thesis), 'abstract')
  end

  should 'send both copyright date fields from the exam date' do
    thesis = build(:thesis, exam_date: Date.new(2026, 8, 5))
    entry = Package.entry(thesis)

    assert_equal ['2026-08-05'], values(entry, 'dateCopyrighted')
    assert_equal ['2026-08-05'], values(entry, 'date.copyright')
  end

  should 'find the full degree name whatever the letter case' do
    thesis = build(:thesis, degree_name: 'ma')

    assert_equal ['MA - Master of Arts'], values(Package.entry(thesis), 'name')
  end

  should 'send the main file first, then supplemental files, never other documents' do
    thesis = create(:thesis)
    supplemental = create(:document, thesis:, supplemental: true, usage: :thesis,
                                     file: fixture_file_upload('pdf-document.pdf'))
    primary = create(:document, thesis:, supplemental: false, usage: :thesis,
                                file: fixture_file_upload('Tony_Rich_E_2012_Phd.pdf'))
    licence = create(:document_licence, thesis:)
    embargo = create(:document, thesis:, supplemental: true, usage: :embargo,
                                file: fixture_file_upload('pdf-document.pdf'))
    modification = create(:document, thesis:, supplemental: true, usage: :modification_request,
                                     file: fixture_file_upload('document-microsoft.doc'))
    request_bound = build(:document, thesis:, usage: :thesis, supplemental: true,
                                     embargo_request: create(:embargo_request, thesis:),
                                     file: fixture_file_upload('document-microsoft.doc'))
    request_bound.save!(validate: false) # legacy row that predates the validation

    assert_equal [primary.file.path, supplemental.file.path], Package.files(thesis)
    assert_equal [primary.file.path], Package.files(thesis, primary_only: true)
    [licence, embargo, modification, request_bound].each do |document|
      assert_not_includes Package.files(thesis), document.file.path
    end
  end

  should 'make the website and the server script send the same record and files' do
    thesis = create(:thesis, supervisor: 'Ada Lovelace / Alan Turing', degree_name: 'phd',
                             abstract: "Para one\u0002.\n\nPara two.", keywords: 'aeronomy; design',
                             exam_date: Date.new(2026, 8, 5))
    create(:document, thesis:, supplemental: false, usage: :thesis,
                      file: fixture_file_upload('Tony_Rich_E_2012_Phd.pdf'))
    create(:document, thesis:, supplemental: true, usage: :thesis,
                      file: fixture_file_upload('pdf-document.pdf'))
    job = DspaceExportJob.new

    assert_equal send(:thesis_to_atom_entry, thesis).to_s, job.thesis_to_atom_entry(thesis).to_s
    assert_equal send(:extract_thesis_filepaths, thesis), job.extract_thesis_filepaths(thesis)
  end

  private

  def values(entry, name)
    entry.extensions.to_a.select { |extension| extension.name == name }.map(&:text)
  end
end
