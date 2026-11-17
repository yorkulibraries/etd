# frozen_string_literal: true
require_relative '../support/graduate_email_browser_case'

# A student can have only one Google connection, so staff must not be able to
# create a Google invitation that would fail when the student uses it.
# Ways this could go wrong, checked below:
# - the box still shows for a student who already has Google connected
# - the box disappears for a student who only uses email codes
# - the box does not come back after the Google connection is removed
# - a direct form post still creates an invitation for a connected student
# Screenshots: tmp/graduate-invitation-when-linked/*.png
class GraduateInvitationWhenLinkedTest < GraduateEmailBrowserCase
  DIR = Rails.root.join('tmp/graduate-invitation-when-linked')
  ALREADY = 'This student already has a Google account connected. To connect a different one, ' \
            'remove the current connection above first.'

  def shot(name)
    FileUtils.mkdir_p(DIR)
    current_window.resize_to(1440, 2200)
    page.save_screenshot(DIR.join("#{name}.png").to_s)
  ensure
    current_window.resize_to(1440, 1000)
  end

  test 'Google invitation box hides while Google is connected and returns after removal' do
    GraduateEmailConnection.create!(student: @student, source: 'record', normalized_address: @student.email,
                                    verified_at: Time.current)
    browser_ppy_login(@actor)

    # Email code only: the Google invitation is still offered.
    visit staff_student_graduate_connections_path(@student)
    assert_selector 'h2', text: 'Create an invitation for a student to connect a secondary email address'
    assert_button 'Create invitation'
    assert_no_text ALREADY
    shot('1-email-only-box-shown')

    # Google connected: no button, a short explanation instead.
    identity = GraduateIdentity.create!(student: @student, linked_by: @student, provider: 'google_oauth2',
                                        uid: 'already-linked-google', link_method: 'record_email')
    visit staff_student_graduate_connections_path(@student)
    assert_selector 'h2', text: 'Create an invitation for a student to connect a secondary email address'
    assert_text ALREADY
    assert_no_button 'Create invitation'
    assert_no_selector '#identity_verified'
    shot('2-google-linked-box-hidden')

    # A direct post is refused too, and nothing is created.
    token = find('meta[name="csrf-token"]', visible: false)[:content]
    assert_no_difference 'GraduateAuthenticationInvitation.count' do
      page.execute_script(<<~JS, student_graduate_invitations_path(@student), token)
        const [url, token] = arguments;
        const f = document.createElement('form'); f.method = 'post'; f.action = url;
        for (const [k, v] of [['authenticity_token', token], ['provider', 'google_oauth2'], ['identity_verified', '1']]) {
          const i = document.createElement('input'); i.type = 'hidden'; i.name = k; i.value = v; f.appendChild(i);
        }
        document.body.appendChild(f); f.submit();
      JS
      assert_text 'already has a Google account connected'
      assert_current_path staff_student_graduate_connections_path(@student)
    end

    # Removing Google brings the box back.
    identity.destroy!
    visit staff_student_graduate_connections_path(@student)
    assert_button 'Create invitation'
    assert_no_text ALREADY
  end
end
