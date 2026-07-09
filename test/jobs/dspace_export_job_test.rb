# frozen_string_literal: true

require 'test_helper'

class DspaceExportJobTest < ActiveSupport::TestCase
  should 'export only primary and thesis supplemental file paths' do
    thesis = create(:thesis)
    primary = create(:document, thesis:, supplemental: false,
                                file: fixture_file_upload('Tony_Rich_E_2012_Phd.pdf'))
    supplemental = create(:document, thesis:, supplemental: true,
                                     file: fixture_file_upload('pdf-document.pdf'))
    licence = create(:document_licence, thesis:)
    embargo = create(:document, thesis:, supplemental: true, usage: :embargo,
                                file: fixture_file_upload('pdf-document.pdf'))
    modification_request = create(:document, thesis:, supplemental: true, usage: :modification_request,
                                             file: fixture_file_upload('document-microsoft.doc'))

    paths = DspaceExportJob.new.extract_thesis_filepaths(thesis)

    assert_includes paths, primary.file.path
    assert_includes paths, supplemental.file.path
    assert_not_includes paths, licence.file.path
    assert_not_includes paths, embargo.file.path
    assert_not_includes paths, modification_request.file.path
  end
end
