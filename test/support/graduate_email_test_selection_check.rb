# frozen_string_literal: true
# Command-level regression gate: real Rails discovery, isolated file trees,
# captured reporter argv. Does not boot the application or touch a database.
require 'json'
require 'open3'
require 'tmpdir'
require 'fileutils'
root = File.expand_path('../..', __dir__)
selection = File.join(root, 'test/support/graduate_email_test_selection.rb')
abort 'SELECTION_CHECK FAIL implementation_missing' unless File.file?(selection)
require selection

def check(label)
  raise 'selection_check_failed' unless yield
  puts "SELECTION_CHECK PASS #{label}"
end

partitions = GraduateEmailTestSelection.partitions
application = Rails::TestUnit::Runner.send(:list_tests, []).to_a.sort
system = Rails::TestUnit::Runner.send(:list_tests, ['test/system']).to_a.sort
check('real_application_coverage') { (partitions.fetch('focused_application') + partitions.fetch('application')).sort == application }
check('real_system_coverage') { (partitions.fetch('focused_system') + partitions.fetch('system')).sort == system }
check('real_disjointness') { partitions.values.flatten.uniq.size == partitions.values.flatten.size }
puts "SELECTION_COUNTS #{partitions.map { |key, files| "#{key}=#{files.size}" }.join(' ')}"

Dir.mktmpdir('graduate-email-selection-') do |fixture|
  %w[script/run_graduate_email_remaining test/support/graduate_email_test_selection.rb].each do |path|
    FileUtils.mkdir_p(File.dirname(File.join(fixture, path)))
    FileUtils.cp(File.join(root, path), File.join(fixture, path))
  end
  FileUtils.cp(File.join(root, '.ruby-version'), fixture)
  files = partitions.values.flatten + ['test/dummy/ignored_test.rb', 'test/system/nested/space name_test.rb']
  files.each { |path| FileUtils.mkdir_p(File.dirname(File.join(fixture, path))); File.write(File.join(fixture, path), '') }
  File.write(File.join(fixture, 'test/support/graduate_email_task5_test_reporter.rb'), "require 'json'; puts JSON.generate(ARGV)\n")
  invoke = lambda do |group, seed = '27183', extra = {}|
    Open3.capture2e({'ETD_SYSTEM_TEST_SEED' => seed, 'DEFAULT_TEST' => nil, 'DEFAULT_TEST_EXCLUDE' => nil}.merge(extra),
      'ruby', File.join(fixture, 'script/run_graduate_email_remaining'), group)
  end
  %w[application system].each do |group|
    output, status = invoke.call(group, '12345')
    argv = JSON.parse(output)
    expected = partitions.fetch(group) + (group == 'system' ? ['test/system/nested/space name_test.rb'] : [])
    check("#{group}_argv_seed") { status.success? && argv == expected.sort + ['-v', '--seed=12345'] }
  end
  output, status = invoke.call('application', '')
  check('blank_seed_default') { status.success? && JSON.parse(output).last == '--seed=27183' }
  [['unknown_group', 'invalid', '27183', {}], ['invalid_seed', 'application', '1;exit', {}],
    ['discovery_override', 'application', '27183', {'DEFAULT_TEST' => 'test/models/**/*_test.rb'}],
    ['overlap_override', 'application', '27183', {'DEFAULT_TEST_EXCLUDE' => 'test/dummy/**/*_test.rb'}]].each do |label, group, seed, env|
    output, status = invoke.call(group, seed, env)
    check(label) { !status.success? && output == "Test selection rejected\n" }
  end
  named = partitions.fetch('focused_application').find { |path| path.end_with?('/google_only_authentication_test.rb') }
  File.rename(File.join(fixture, named), File.join(fixture, named + '.hidden'))
  output, status = invoke.call('application')
  check('missing_expected_file') { !status.success? && output == "Test selection rejected\n" }
  File.rename(File.join(fixture, named + '.hidden'), File.join(fixture, named))
  Dir[File.join(fixture, 'test/integration/graduate_email_*_test.rb')].each { |path| File.unlink(path) }
  output, status = invoke.call('application')
  check('empty_dynamic_focus') { !status.success? && output == "Test selection rejected\n" }
  partitions.fetch('focused_application').grep(/graduate_email_/).each { |path| File.write(File.join(fixture, path), '') }
  partitions.fetch('application').each { |path| File.unlink(File.join(fixture, path)) }
  output, status = invoke.call('application')
  check('empty_remaining') { !status.success? && output == "Test selection rejected\n" }
end
