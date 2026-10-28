# frozen_string_literal: true
require 'json'
require 'digest'
require 'fileutils'
require 'uri'
require 'base64'

# Automatic screenshots/HTML and historical browser_artifact calls stay disabled.
# The separate explicit API accepts only reviewed clean states, never token pages.
module GraduateEmailSafeArtifacts
  class UnsafeArtifact < StandardError
    def initialize; super('unsafe_artifact'); end
  end
  STATES = {
    'login' => [%r{\A/graduate/login\z}, 'Graduate sign in'],
    'generic-send' => [%r{\A/graduate/email/(?:challenges|resend|verify)\z}, 'Enter your sign-in code'],
    'code-error' => [%r{\A/graduate/email/verify\z}, 'Enter your sign-in code'],
    'expired-enrollment' => [%r{\A/graduate/email/verify\z}, 'Request your sign-in code'],
    'revoked-enrollment' => [%r{\A/graduate/email/verify\z}, 'Request your sign-in code'],
    'student-connection' => [%r{\A/my/graduate-connections\z}, 'Email sign-in'],
    'staff-confirmation' => [%r{\A/students/\d+/graduate-connections\z}, 'Approve email sign-in'],
    'staff-recovery' => [%r{\A/students/\d+/graduate-connections\z}, 'Replace or recover email sign-in'],
    'staff-review' => [%r{\A/students/\d+/graduate-email-invitations/review\z}, 'Review email sign-in address'],
    'staff-conflict' => [%r{\A/students/\d+/graduate-email-invitations/review\z}, 'Review email sign-in address'],
    'notice-states' => [%r{\A/students/\d+/graduate-connections\z}, 'Email change notices']
  }.freeze
  SENTINELS = %w[TASK7_ARTIFACT_SENTINEL ARTIFACT_SENTINEL].freeze
  REPORTS = %w[fresh.txt upgrade.txt integration.txt system.txt versions.txt source.json result.json].freeze
  ROOT = File.expand_path('../..', __dir__)

  # Optional named runs preserve historical packages during local verification.
  def self.verification_directory(adapter)
    raise UnsafeArtifact unless %w[sqlite mysql].include?(adapter)
    run = ENV['GRADUATE_EMAIL_VERIFICATION_RUN']
    raise UnsafeArtifact if run && !run.match?(/\A[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}\z/)
    File.join(ROOT, 'tmp/graduate-email/verification', *[run, adapter].compact)
  end

  def self.clean_state?(name, state)
    route, heading = STATES[name]
    !!(route && state[:path].to_s.match?(route) && state[:heading] == heading &&
      state[:query] == false && state[:secret] == false && state[:entered] == false &&
      [[1440, 1000], [390, 844]].include?([state[:width], state[:height]]))
  end

  DIAGNOSTIC_FLAGS = {query: :query, secret: :secret, entered: :entered,
    attribute: :attribute_secret, text: :text_secret, invitation: :invitation_secret,
    link: :link_secret, input: :input_secret}.freeze
  DIAGNOSTIC_LINE = /\AARTIFACT_GUARD state=(?:#{(STATES.keys + ['unknown']).join('|')}) width=[0-9]{1,5} height=[0-9]{1,5} route=[01] heading=[01]#{DIAGNOSTIC_FLAGS.keys.map { |key| " #{key}=[01]" }.join}\z/

  # Diagnostics contain only reviewed state names, bounded sizes and booleans.
  # Never interpolate paths, headings, attributes, input values or exceptions.
  def self.guard_diagnostic(name, state)
    route, heading = STATES[name]
    size = %i[width height].map do |key|
      value = state[key]
      value.is_a?(Integer) && value.between?(0, 99_999) ? value : 0
    end
    flags = DIAGNOSTIC_FLAGS.map { |label, key| "#{label}=#{state[key] == true ? 1 : 0}" }
    "ARTIFACT_GUARD state=#{STATES.key?(name) ? name : 'unknown'} width=#{size[0]} height=#{size[1]} " +
      "route=#{route && state[:path].to_s.match?(route) ? 1 : 0} heading=#{heading && state[:heading] == heading ? 1 : 0} " + flags.join(' ')
  end

  def self.test_identities
    Dir[File.join(ROOT, 'test/{integration,system}/*_test.rb')].flat_map do |file|
      source = File.read(file)
      source.split(/^class ([A-Za-z0-9]+) <[^\n]+\n/).drop(1).each_slice(2).flat_map do |klass, body|
        body.scan(/test(?: |\()['"]([a-zA-Z0-9_ ]+)['"]/).map { |name| [klass, 'test_' + name.first.tr(' ', '_')] }
      end
    end
  end

  def self.sanitize_report(output)
    identities = test_identities
    lines = output.lines.filter_map do |line|
      line = line.strip
      if line.match?(DIAGNOSTIC_LINE)
        line
      elsif line.match?(/\A\d+ runs, \d+ assertions, \d+ failures, \d+ errors, \d+ skips\z/) ||
          line.match?(/\A--seed [0-9]+\z/)
        line
      elsif (match = line.match(/\A(?:TEST )?([A-Za-z0-9]+)(?:#| )(test_[a-zA-Z0-9_]+)/)) && identities.include?([match[1], match[2]])
        result = line[/ (?:=|RESULT) ([.FES])\z/, 1]
        "TEST #{match[1]} #{match[2]}" + (result ? " RESULT #{result}" : "")
      elsif line.match?(/\A(?:ADMISSION|DELIVERY)_COUNTS [a-z_ =0-9]+\z/)
        line
      end
    end
    %w[RuntimeError JavascriptError NameError NoMethodError ArgumentError SyntaxError Timeout::Error InvalidAuthenticityToken
       Capybara::ElementNotFound GraduateEmailSafeArtifacts::UnsafeArtifact ActiveRecord::StatementInvalid ActiveRecord::RecordInvalid].each do |category|
      lines << "CATEGORY #{category}" if output.include?(category)
    end
    output.scan(%r{test/(?:integration|system|support)/[a-z0-9_]+\.rb:[0-9]+}).uniq.each do |location|
      file = location.split(':').first
      lines << "LOCATION #{location}" if File.file?(File.join(ROOT, file))
    end
    lines.join("\n") + "\n"
  end

  def self.allowed_file?(name)
    REPORTS.include?(name) || name == 'manifest.json' ||
      STATES.keys.any? { |state| %w[desktop mobile].any? { |size| name == "#{state}-#{size}.png" } }
  end

  def self.scan!(directory, sentinels: SENTINELS)
    raise UnsafeArtifact if File.symlink?(directory)
    Dir.children(directory).each do |name|
      path = File.join(directory, name)
      raise UnsafeArtifact unless allowed_file?(name) && File.file?(path) && !File.symlink?(path)
      bytes = File.binread(path)
      raise UnsafeArtifact if sentinels.any? { |value| !value.empty? && bytes.include?(value) }
      if name.end_with?('.png')
        raise UnsafeArtifact unless bytes.start_with?("\x89PNG\r\n\x1a\n".b)
      else
        # No URLs, mail recipients, bearer assignments or raw HTML in reports.
        raise UnsafeArtifact if bytes.match?(%r{https?://|[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+|(?:token|code|password|cookie)\s*[=:]|<html|<!DOCTYPE}i)
      end
    end
    true
  end

  def self.write_manifest(directory, metadata:)
    raise UnsafeArtifact unless metadata.keys.sort == %i[adapter branch diff_sha256 head seed source_sha256].sort &&
      %w[sqlite mysql].include?(metadata[:adapter]) && metadata[:branch].match?(/\A[a-zA-Z0-9_\/-]+\z/) &&
      metadata[:head].match?(/\A[0-9a-f]{40}\z/) && metadata[:seed].is_a?(Integer) && metadata[:seed] >= 0 &&
      %i[diff_sha256 source_sha256].all? { |key| metadata[key].match?(/\A[0-9a-f]{64}\z/) }
    scan!(directory)
    files = Dir.children(directory).sort.reject { |name| name == 'manifest.json' }.to_h do |name|
      [name, Digest::SHA256.file(File.join(directory, name)).hexdigest]
    end
    File.write(File.join(directory, 'manifest.json'), JSON.pretty_generate(metadata.merge(files: files)) + "\n")
    scan!(directory)
  end

  def browser_artifact(*, **); end
  def take_screenshot; end
  def take_failed_screenshot; end

  def clean_browser_artifact(name, mobile: false)
    raise UnsafeArtifact unless STATES.key?(name)
    resize_clean_viewport(mobile ? [390, 844] : [1440, 1000])
    assert_selector 'main'
    expected = STATES.fetch(name).last
    assert_text expected
    state = page.evaluate_script(<<~JS, expected).transform_keys(&:to_sym)
      ((expected) => {
        const withoutEmail = value => value.replace(/[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+/g, "");
        const secretValue = value => /(?:^|[^0-9])[0-9]{6}(?:[^0-9]|$)|[a-f0-9]{64}|[A-Za-z0-9_-]{43,}/i.test(withoutEmail(value));
        const values = Array.from(document.querySelectorAll('input,textarea')).filter(e => e.name !== 'authenticity_token');
        const links = Array.from(document.querySelectorAll('a')).map(e => e.getAttribute('href') || '');
        const unsafeAttributes = Array.from(document.querySelectorAll('*')).some(e => Array.from(e.attributes).some(a => {
          // The sole dynamic DOM exception is the real Rails CSRF boundary.
          if (e.matches('meta[name="csrf-token"]') && a.name === 'content') return false;
          if (e.matches('input[type="hidden"][name="authenticity_token"]') && a.name === 'value') return false;
          // Asset digests are reviewed static build identifiers, never auth URLs.
          if (['SCRIPT','LINK','IMG'].includes(e.tagName) && ['src','href'].includes(a.name) &&
              a.value.startsWith('/assets/') && !/[?#]/.test(a.value) &&
              /[.](?:js|css|png|gif|svg|ico|woff2?)$/.test(a.value)) return false;
          return /token|password/i.test(a.name) || secretValue(a.value);
        }));
        const textSecret = secretValue(document.documentElement.textContent);
        const invitationSecret = /Share this invitation once/.test(document.body.innerText);
        const linkSecret = links.some(v => /[?&](token|code)=/i.test(v));
        const inputSecret = values.some(e => /token|password/i.test(e.name) || secretValue(e.value));
        const secret = unsafeAttributes || textSecret || invitationSecret || linkSecret || inputSecret;
        return {path: location.pathname, query: !!(location.search || location.hash), secret,
          entered: values.some(e => e.name === 'code' && e.value !== ''),
          heading: Array.from(document.querySelectorAll('h1,h2')).some(e => e.textContent.trim() === expected) ? expected : '',
          width: innerWidth, height: innerHeight, attribute_secret: unsafeAttributes,
          text_secret: textSecret, invitation_secret: invitationSecret, link_secret: linkSecret, input_secret: inputSecret};
      })(arguments[0])
    JS
    unless GraduateEmailSafeArtifacts.clean_state?(name, state)
      warn GraduateEmailSafeArtifacts.guard_diagnostic(name, state)
      raise UnsafeArtifact
    end
    assert page.evaluate_script('document.documentElement.scrollWidth <= document.documentElement.clientWidth'), 'clean state overflow'
    # General suites perform every clean-state/layout assertion without writing.
    directory = ENV['GRADUATE_EMAIL_ARTIFACT_DIR']
    return nil unless directory
    expected_directory = GraduateEmailSafeArtifacts.verification_directory(ENV['DB_ADAPTER'] == 'mysql2' ? 'mysql' : 'sqlite')
    raise UnsafeArtifact unless directory == expected_directory && !File.symlink?(directory)
    raise UnsafeArtifact if File.exist?(File.join(directory, 'manifest.json'))
    FileUtils.mkdir_p(directory)
    browser = page.driver.browser
    size = browser.execute_cdp('Page.getLayoutMetrics').fetch('cssContentSize')
    shot = browser.execute_cdp('Page.captureScreenshot', captureBeyondViewport: true,
      clip: {x: 0, y: 0, width: state.fetch(:width), height: size.fetch('height'), scale: 1})
    path = File.join(directory, "#{name}-#{mobile ? 'mobile' : 'desktop'}.png")
    File.binwrite(path, Base64.decode64(shot.fetch('data')))
    path
  ensure
    resize_clean_viewport([1440, 1000]) if mobile
  end

  private

  # WebDriver sizes the outer window. New headless Chrome includes browser
  # chrome in that size, so compensate and verify the exact inner viewport.
  def resize_clean_viewport(target)
    current_window.resize_to(*target)
    3.times do
      actual = page.evaluate_script('[innerWidth, innerHeight]')
      return if actual == target
      outer = current_window.size
      current_window.resize_to(*outer.zip(target, actual).map { |size, wanted, measured| size + wanted - measured })
    end
    raise UnsafeArtifact unless page.evaluate_script('[innerWidth, innerHeight]') == target
  end

  def save_html; end
  def save_image; end
end
