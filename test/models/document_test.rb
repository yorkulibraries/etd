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

    # should not be able to create a primary file with extension .jpg 
    doc = build(:document, usage: 'thesis', supplemental: false, file: fixture_file_upload('image-example.jpg'))
    assert '.jpg', doc.file_extension
    assert !doc.valid_extension?, 'extension .jpg should not be valid for primary file'
    assert doc.primary?, "must be primary"
    assert !doc.supplemental?, "must not be supplemental"
    assert_equal 'thesis', doc.usage, 'usage must be "thesis"'
    assert !doc.valid?, 'Should not be valid, extension cannot be .jpg'

    # should not be able to create a primary file with usage "licence"
    doc = build(:document, usage: 'licence', supplemental: false, file: fixture_file_upload('pdf-document.pdf'))
    assert '.pdf', doc.file_extension
    assert doc.valid_extension?, 'extension should be valid'
    assert doc.primary?, "must be primary"
    assert_equal 'licence', doc.usage, 'usage must be "licence"'
    assert !doc.valid?, 'Should not be valid, usage can not be "licence" AND not supplemental'

    # should not be able to create a primary file with usage "embargo"
    doc = build(:document, usage: 'embargo', supplemental: false, file: fixture_file_upload('pdf-document.pdf'))
    assert '.pdf', doc.file_extension
    assert doc.valid_extension?, 'extension should be valid'
    assert doc.primary?, "must be primary"
    assert_equal 'embargo', doc.usage, 'usage must be "embargo"'
    assert !doc.valid?, 'Should not be valid, usage can not be "embargo" AND not supplemental'
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
    assert File.exist?(d.file.path)
  end

  should 'update the file when it changes' do
    d = create(:document)
    d.file = fixture_file_upload('html-document.html', 'text/html')
    assert d.save, "should save properly #{d.errors.inspect}"

    assert File.exist?(d.file.path)
  end

  should 'update the file when it changes' do
    d = create(:document, supplemental: false, file: fixture_file_upload('Tony_Rich_E_2012_Phd.pdf'))

    assert File.exist?(d.file.path)
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

  should 'supplemental files must follow file naming convention' do
    t = create(:thesis)
    assert_equal 0, t.documents.count

    original_filename = 'pdf-document.pdf'
    d = create(:document_for_file_naming, file: fixture_file_upload(original_filename), usage: :thesis, supplemental: false, thesis: t)
    
    # make sure the document is valid 
    assert d.valid?, 'should be valid'

    # document should be primary
    assert !d.supplemental, 'should not be supplimental'
    assert_equal "primary", d.document_type

    assert d.usage, :thesis

    # should only have 1 document so far
    assert_equal 1, t.documents.count

    # the uploaded file name should match
    uploaded_filename = d.uploaded_filename(original_filename)
    assert_equal uploaded_filename, d.file.filename

    # the file name should start with student name
    student_name = t.student.name.gsub(/[\s\.]/, '_')
    assert_match /^#{student_name}_.+/, uploaded_filename, "file name should start with #{student_name}"

    # the file name should end with degree_name.pdf
    degree_name = t.degree_name.gsub(/[\s\.]/, '_')
    assert_match /#{degree_name}.pdf$/, uploaded_filename, "the file name should end with #{degree_name}.pdf"

    # the file name should contain _year_ 
    year = t.exam_date.year
    assert_match /_#{year}_/, uploaded_filename, "the file name should contain _#{year}_"

    # the file name should contain _degree_name
    degree_name = t.degree_name.gsub(/[\s\.]/, '_')
    assert_match /_#{degree_name}/, uploaded_filename, "the file name should contain _#{degree_name}"

    # now upload first supplimentary file
    d = create(:document_for_file_naming, file: fixture_file_upload(original_filename), usage: :thesis, supplemental: true, thesis: t)
    
    # make sure the document is valid 
    assert d.valid?, 'should be valid'

    # document should be supplimental
    assert d.supplemental, 'should be supplimental'
    assert_equal "supplemental", d.document_type

    # now there should be 2 files
    assert_equal 2, t.documents.count

    # the uploaded file name should match
    uploaded_filename = d.uploaded_filename(original_filename)
    assert_equal uploaded_filename, d.file.filename

    # file name should end with _supplemental_1.pdf
    assert_match /_supplemental_1.pdf$/, uploaded_filename, "the file name should end with _supplemental_1.pdf"

    # now upload 2nd supplementary file
    d = create(:document_for_file_naming, file: fixture_file_upload(original_filename), usage: :thesis, supplemental: true, thesis: t)

    # make sure the document is valid 
    assert d.valid?, 'should be valid'

    # document should be supplimental
    assert d.supplemental, 'should be supplimental'
    assert_equal "supplemental", d.document_type

    # now there should be 3 files
    assert_equal 3, t.documents.count

    # the uploaded file name should match
    uploaded_filename = d.uploaded_filename(original_filename)
    assert_equal uploaded_filename, d.file.filename

    # file name should end with _supplemental_2.pdf
    assert_match /_supplemental_2.pdf$/, uploaded_filename, "the file name should end with _supplemental_2.pdf"

    # now "delete" the s2 file
    d.destroy

    # now there should STILL be 3 files because the file was only "marked as deleted"
    assert_equal 3, t.documents.count

    # but there should only be 2 not_deleted files
    assert_equal 2, t.documents.not_deleted.count

    # now upload 3rd supplementary file
    d = create(:document_for_file_naming, file: fixture_file_upload(original_filename), usage: :thesis, supplemental: true, thesis: t)

    # document should be supplimental
    assert d.supplemental, 'should be supplimental'
    assert_equal "supplemental", d.document_type

    # now there should be 4 files
    assert_equal 4, t.documents.count

    # but there should only be 3 not_deleted files
    assert_equal 3, t.documents.not_deleted.count

    # the uploaded file name should match
    uploaded_filename = d.uploaded_filename(original_filename)
    assert_equal uploaded_filename, d.file.filename

    # file name should end with _supplemental_3.pdf
    assert_match /_supplemental_3.pdf$/, uploaded_filename, "the file name should end with _supplemental_3.pdf"
  end

  should 'licence files must follow file naming convention' do
    t = create(:thesis)
    assert_equal 0, t.documents.count

    original_filename = 'pdf-document.pdf'
    d = create(:document_for_file_naming, file: fixture_file_upload(original_filename), usage: :thesis, supplemental: false, thesis: t)
    
    # make sure the document is valid 
    assert d.valid?, 'should be valid'

    # document should be primary
    assert !d.supplemental, 'should not be supplimental'
    assert_equal "primary", d.document_type

    assert d.usage, :thesis

    # should only have 1 document so far
    assert_equal 1, t.documents.count

    # the uploaded file name should match
    uploaded_filename = d.uploaded_filename(original_filename)
    assert_equal uploaded_filename, d.file.filename

    # the file name should start with student name
    student_name = t.student.name.gsub(/[\s\.]/, '_')
    assert_match /^#{student_name}_.+/, uploaded_filename, "file name should start with #{student_name}"

    # the file name should end with degree_name.pdf
    degree_name = t.degree_name.gsub(/[\s\.]/, '_')
    assert_match /#{degree_name}.pdf$/, uploaded_filename, "the file name should end with #{degree_name}.pdf"

    # the file name should contain _year_ 
    year = t.exam_date.year
    assert_match /_#{year}_/, uploaded_filename, "the file name should contain _#{year}_"

    # the file name should contain _degree_name
    degree_name = t.degree_name.gsub(/[\s\.]/, '_')
    assert_match /_#{degree_name}/, uploaded_filename, "the file name should contain _#{degree_name}"

    # now upload first licence file
    d = create(:document_for_file_naming, file: fixture_file_upload(original_filename), usage: :licence, supplemental: true, thesis: t)
    
    # make sure the document is valid 
    assert d.valid?, 'should be valid'

    # document should be supplimental
    assert d.supplemental, 'should be supplimental'
    assert_equal "licence", d.document_type

    # now there should be 2 files
    assert_equal 2, t.documents.count

    # the uploaded file name should match
    uploaded_filename = d.uploaded_filename(original_filename)
    assert_equal uploaded_filename, d.file.filename

    # file name should end with _licence_1.pdf
    assert_match /_licence_1.pdf$/, uploaded_filename, "the file name should end with _licence_1.pdf"

    # now upload 2nd licence file
    d = create(:document_for_file_naming, file: fixture_file_upload(original_filename), usage: :licence, supplemental: true, thesis: t)

    # make sure the document is valid 
    assert d.valid?, 'should be valid'

    # document should be supplimental
    assert d.supplemental, 'should be supplimental'
    assert_equal "licence", d.document_type

    # now there should be 3 files
    assert_equal 3, t.documents.count

    # the uploaded file name should match
    uploaded_filename = d.uploaded_filename(original_filename)
    assert_equal uploaded_filename, d.file.filename

    # file name should end with _licence_2.pdf
    assert_match /_licence_2.pdf$/, uploaded_filename, "the file name should end with _licence_2.pdf"

    # now "delete" the s2 file
    d.destroy

    # now there should STILL be 3 files because the file was only "marked as deleted"
    assert_equal 3, t.documents.count

    # but there should only be 2 not_deleted files
    assert_equal 2, t.documents.not_deleted.count

    # now upload 3rd licence file
    d = create(:document_for_file_naming, file: fixture_file_upload(original_filename), usage: :licence, supplemental: true, thesis: t)

    # document should be supplimental
    assert d.supplemental, 'should be supplimental'
    assert_equal "licence", d.document_type

    # now there should be 4 files
    assert_equal 4, t.documents.count

    # but there should only be 3 not_deleted files
    assert_equal 3, t.documents.not_deleted.count

    # the uploaded file name should match
    uploaded_filename = d.uploaded_filename(original_filename)
    assert_equal uploaded_filename, d.file.filename

    # file name should end with _supplemental_3.pdf
    assert_match /_licence_3.pdf$/, uploaded_filename, "the file name should end with _licence_3.pdf"
  end

  should 'embargo files must follow file naming convention' do
    t = create(:thesis)
    assert_equal 0, t.documents.count

    original_filename = 'pdf-document.pdf'
    d = create(:document_for_file_naming, file: fixture_file_upload(original_filename), usage: :thesis, supplemental: false, thesis: t)
    
    # make sure the document is valid 
    assert d.valid?, 'should be valid'

    # document should be primary
    assert !d.supplemental, 'should not be supplimental'
    assert_equal "primary", d.document_type

    assert d.usage, :thesis

    # should only have 1 document so far
    assert_equal 1, t.documents.count

    # the uploaded file name should match
    uploaded_filename = d.uploaded_filename(original_filename)
    assert_equal uploaded_filename, d.file.filename

    # the file name should start with student name
    student_name = t.student.name.gsub(/[\s\.]/, '_')
    assert_match /^#{student_name}_.+/, uploaded_filename, "file name should start with #{student_name}"

    # the file name should end with degree_name.pdf
    degree_name = t.degree_name.gsub(/[\s\.]/, '_')
    assert_match /#{degree_name}.pdf$/, uploaded_filename, "the file name should end with #{degree_name}.pdf"

    # the file name should contain _year_ 
    year = t.exam_date.year
    assert_match /_#{year}_/, uploaded_filename, "the file name should contain _#{year}_"

    # the file name should contain _degree_name
    degree_name = t.degree_name.gsub(/[\s\.]/, '_')
    assert_match /_#{degree_name}/, uploaded_filename, "the file name should contain _#{degree_name}"

    # now upload first licence file
    d = create(:document_for_file_naming, file: fixture_file_upload(original_filename), usage: :embargo, supplemental: true, thesis: t)
    
    # make sure the document is valid 
    assert d.valid?, 'should be valid'

    # document should be supplimental
    assert d.supplemental, 'should be supplimental'
    assert_equal "embargo", d.document_type

    # now there should be 2 files
    assert_equal 2, t.documents.count

    # the uploaded file name should match
    uploaded_filename = d.uploaded_filename(original_filename)
    assert_equal uploaded_filename, d.file.filename

    # file name should end with _embargo_1.pdf
    assert_match /_embargo_1.pdf$/, uploaded_filename, "the file name should end with _embargo_1.pdf"

    # now upload 2nd licence file
    d = create(:document_for_file_naming, file: fixture_file_upload(original_filename), usage: :embargo, supplemental: true, thesis: t)

    # make sure the document is valid 
    assert d.valid?, 'should be valid'

    # document should be supplimental
    assert d.supplemental, 'should be supplimental'
    assert_equal "embargo", d.document_type

    # now there should be 3 files
    assert_equal 3, t.documents.count

    # the uploaded file name should match
    uploaded_filename = d.uploaded_filename(original_filename)
    assert_equal uploaded_filename, d.file.filename

    # file name should end with _embargo_2.pdf
    assert_match /_embargo_2.pdf$/, uploaded_filename, "the file name should end with _embargo_2.pdf"

    # now "delete" the s2 file
    d.destroy

    # now there should STILL be 3 files because the file was only "marked as deleted"
    assert_equal 3, t.documents.count

    # but there should only be 2 not_deleted files
    assert_equal 2, t.documents.not_deleted.count

    # now upload 3rd licence file
    d = create(:document_for_file_naming, file: fixture_file_upload(original_filename), usage: :embargo, supplemental: true, thesis: t)

    # document should be supplimental
    assert d.supplemental, 'should be supplimental'
    assert_equal "embargo", d.document_type

    # now there should be 4 files
    assert_equal 4, t.documents.count

    # but there should only be 3 not_deleted files
    assert_equal 3, t.documents.not_deleted.count

    # the uploaded file name should match
    uploaded_filename = d.uploaded_filename(original_filename)
    assert_equal uploaded_filename, d.file.filename

    # file name should end with _embargo_3.pdf
    assert_match /_embargo_3.pdf$/, uploaded_filename, "the file name should end with _embargo_3.pdf"
  end

  should 'list primary and suplemental files' do
    create_list(:document, 2, supplemental: false, file: fixture_file_upload('Tony_Rich_E_2012_Phd.pdf'))
    create_list(:document, 4, supplemental: true)

    assert_equal 6, Document.count, 'There should be nine in total'
    assert_equal 4, Document.supplemental.count, 'The should be 4 supplemental documents'
    assert_equal 2, Document.primary.count, 'There should be 5 primary documents'
  end

  should 'allowed_extensions should match document usage' do
    d = Document.new
    
    d.usage = 'thesis'
    d.supplemental = false
    assert_equal Document::PRIMARY_FILE_EXT, d.allowed_extensions

    d.usage = 'thesis'
    d.supplemental = true
    assert_equal Document::SUPPLEMENTAL_FILE_EXT, d.allowed_extensions

    d.usage = 'licence'
    d.supplemental = false
    assert_equal Document::LICENCE_FILE_EXT, d.allowed_extensions

    d.usage = 'licence'
    d.supplemental = true
    assert_equal Document::LICENCE_FILE_EXT, d.allowed_extensions

    d.usage = 'embargo'
    d.supplemental = false
    assert_equal Document::EMBARGO_FILE_EXT, d.allowed_extensions

    d.usage = 'embargo'
    d.supplemental = true
    assert_equal Document::EMBARGO_FILE_EXT, d.allowed_extensions
  end
end
