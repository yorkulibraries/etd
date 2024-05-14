# frozen_string_literal: true

require 'test_helper'

class DocumentTest < ActiveSupport::TestCase
  should 'display newest/oldest documents' do
    newer = create(:document, created_at: 3.days.ago)
    older = create(:document, created_at: 1.year.ago)

    assert_equal newer.id, Document.newest.first.id, 'Newest should be first'
    assert_equal older.id, Document.oldest.first.id, 'Oldest should be first'
  end

  should 'create a proper document' do
    d = build(:document)

    assert d.valid?, 'Valid document'

    assert_difference 'Document.count', 1 do
      d.save
    end
  end

  should 'not create an invalid document' do
    assert !build(:document, file: nil).valid?, 'File is required'
    assert !build(:document, user: nil).valid?, 'User/owner is required'
    assert !build(:document, thesis: nil).valid?, 'Thesis is required'
  end

  should 'only allow one primary file per thesis, and it should ignore deleted' do
    thesis = create(:thesis)
    create(:document, thesis:, supplemental: false, file: fixture_file_upload('Tony_Rich_E_2012_Phd.pdf'))

    assert !build(:document, thesis:, supplemental: false, file: fixture_file_upload('Tony_Rich_E_2012_Phd.pdf')).valid?,
           'Already have one primary, so it should fails'
    assert build(:document, thesis:, supplemental: false, deleted: true, file: fixture_file_upload('Tony_Rich_E_2012_Phd.pdf')).valid?,
           'If its a deleted file it should be ok'
  end

  should 'upload non-image files without complaining' do
    d = build(:document, file: nil)
    d.file = fixture_file_upload('html-document.html', 'text/html')

    assert d.save, 'Should save this properly'
    assert_equal "/uploads/theses/#{d.thesis.id}/files/#{d.id}/html-document.html", d.file.url,
                 'file should be uploaded'
  end

  should 'update the file when it changes' do
    d = create(:document)
    d.file = fixture_file_upload('html-document.html', 'text/html')
    assert d.save, "should save properly #{d.errors.inspect}"

    assert_equal "/uploads/theses/#{d.thesis.id}/files/#{d.id}/html-document.html", d.file.url
  end

  should 'update the file when it changes' do
    d = create(:document, supplemental: false, file: fixture_file_upload('Tony_Rich_E_2012_Phd.pdf'))

    assert_equal "/uploads/theses/#{d.thesis.id}/files/#{d.id}/Tony_Rich_E_2012_Phd.pdf", d.file.url
  end

  should 'not destroy files, set deleted flag instead' do
    d = create(:document)

    assert_no_difference 'Document.count' do
      d.destroy
    end

    assert d.deleted?, 'Deleted flag is set'
  end

  should 'list deleted and non-deleted files' do
    create_list(:document, 4, deleted: false)
    create_list(:document, 2, deleted: true)

    assert_equal 4, Document.not_deleted.count, '4 Not deleted'
    assert_equal 2, Document.deleted.count, '2 deleted'
  end

  should 'tell if file is image or not' do
    d = create(:document, file: fixture_file_upload('html-document.html', 'text/html'))

    assert !d.image?, 'Should not be an image'

    d = create(:document, file: fixture_file_upload('image-example.jpg', 'image/jpg'))

    assert d.image?, 'This one should be an image'
  end

  should 'automatic naming for primary file FullNameField_Year_Degree_Primary.pdf' do
    
    document_name = 'pdf-document.pdf'
    t = create(:thesis)
    d = create(:document_for_file_naming, file: fixture_file_upload(document_name), usage: :thesis, supplemental: false, thesis: t)
    expected = Document.filename_by_convention(d.user.name, d.thesis.exam_date, d.thesis.degree_name, d.thesis.degree_level, document_name, d.supplemental, d.usage)

    assert_equal expected, d.file.filename
    assert_match(/_Primary\.\w+$/, t.documents.first.file.to_s)
  end

  should 'automate naming for supplementary file FullNameField_Year_Degree_Supplementary_1.file extension' do 
    
    document_name = 'pdf-document.pdf'
    t = create(:thesis)
    d = create(:document_for_file_naming, file: fixture_file_upload(document_name), usage: :thesis, supplemental: true, thesis: t)
    expected = Document.filename_by_convention(d.user.name, d.thesis.exam_date, d.thesis.degree_name, d.thesis.degree_level, document_name, d.supplemental, d.usage)

    assert_equal expected, d.file.filename
    assert_match(/_Supplemental_.*\.\w+$/, t.documents.first.file.to_s)
  end

  should 'save files in sequence for supplementary' do
  #   t = create(:thesis)
    
  #   d = create(:document_for_file_naming, file: fixture_file_upload('pdf-document.pdf'), usage: :thesis, supplemental: true, thesis: t)
  #   d2 = create(:document_for_file_naming, file: fixture_file_upload('html-document.html'), usage: :thesis, supplemental: true, thesis: t)
  #   d3 = create(:document_for_file_naming, file: fixture_file_upload('image-example.jpg'), usage: :thesis, supplemental: true, thesis: t)

  #   # puts "\n\nDEBUGGING F1\n #{d.pretty_inspect()}"
  #   # puts "\n\nDEBUGGING F2\n #{d2.pretty_inspect()}"
  #   # puts "\n\nDEBUGGING F3\n #{d3.pretty_inspect()}"

  #   # Assert that the filename ends with "_1"
  #   assert_match(/_1\.\w+$/, t.documents.first.file.to_s)
  #   assert_match(/_3\.\w+$/, t.documents.last.file.to_s)

  #   ## Count should still increment even if deleted because files are only flagged as deleted.
  #   d.destroy
  #   d4 = create(:document_for_file_naming, file: fixture_file_upload('papyrus-feature.png'), usage: :thesis, supplemental: true, thesis: t)
  #   assert_match(/_4\.\w+$/, t.documents.last.file.to_s)
  end

  should 'None naming convention for non-existence of usage' do
    document_name = 'html-document.html'
    d = create(:document_for_naming, file: fixture_file_upload(document_name, 'text/html'))
    assert_equal document_name, d.file.filename
  end

  should 'list primary and suplemental files' do
    create_list(:document, 2, supplemental: false, file: fixture_file_upload('Tony_Rich_E_2012_Phd.pdf'))
    create_list(:document, 4, supplemental: true)

    assert_equal 6, Document.count, 'There should be nine in total'
    assert_equal 4, Document.supplemental.count, 'The shoudl be 4 supplemental documents'
    assert_equal 2, Document.primary.count, 'There should be 5 primary documents'
  end
end
