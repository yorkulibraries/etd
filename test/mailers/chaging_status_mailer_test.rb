require 'test_helper'

class ChagingStatusMailerTest < ActionMailer::TestCase
  test 'published' do
    EMAIL = 'email@domain.com'
    mail = ChagingStatusMailer.published(EMAIL)
    assert_equal 'The status of your thesis has been changed.', mail.subject
    assert_equal [EMAIL], mail.to
    assert_equal ['noreply@yorku.ca'], mail.from
    assert_match 'The status of the thesis has changed to "Published".', mail.body.encoded
  end
end
