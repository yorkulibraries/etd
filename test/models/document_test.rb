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
    create(:document, thesis: thesis, supplemental: false)

    assert !build(:document, thesis: thesis, supplemental: false).valid?,
           'Already have one primary, so it should fails'
    assert build(:document, thesis: thesis, supplemental: false, deleted: true).valid?,
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

  should 'list primary and suplemental files' do
    create_list(:document, 5, supplemental: false)
    create_list(:document, 4, supplemental: true)

    assert_equal 9, Document.count, 'There should be nine in total'
    assert_equal 4, Document.supplemental.count, 'The shoudl be 4 supplemental documents'
    assert_equal 5, Document.primary.count, 'There should be 5 primary documents'
  end
end
