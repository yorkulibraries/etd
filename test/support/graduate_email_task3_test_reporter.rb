# frozen_string_literal: true
# Keep raw test diagnostics in memory. Reports expose only static method names,
# known exception categories and numeric summaries, never assertion values.
require 'open3'
report = ENV['TASK3_REPORT'] && File.open(File.expand_path('../../..', __FILE__) + '/tmp/graduate-email/' + File.basename(ENV['TASK3_REPORT']), 'w')
emit = ->(line) { puts line; report&.puts(line); report&.flush }
output, status = Open3.capture2e('bundle', 'exec', 'rails', 'test', *ARGV)
output.lines.each do |line|
  stripped = line.strip
  if stripped.match?(/\A\d+ runs, \d+ assertions, \d+ failures, \d+ errors, \d+ skips\z/) ||
      stripped.match?(/\AADMISSION_COUNTS [a-z_ =0-9]+\z/) ||
      stripped.match?(/\AADMISSION_(?:ERROR|LOCATION) [A-Za-z0-9_.:]+\z/)
    emit.call stripped
  elsif (match = stripped.match(/\A([A-Z][A-Za-z0-9]+)#(test_[a-zA-Z0-9_]+)/))
    emit.call "TEST_DIAGNOSTIC #{match[1]} #{match[2]}"
  elsif (match = stripped.match(/\A(test_[a-zA-Z0-9_]+)\(([A-Za-z0-9]+)\)(?:\s|:|\[)/))
    emit.call "TEST_DIAGNOSTIC #{match[2]} #{match[1]}"
  elsif (match = stripped.match(/(?:test\/(?:integration|support)\/[a-z_]+\.rb:\d+)/))
    emit.call "TEST_LOCATION #{match[0]}"
  elsif (match = stripped.match(/ADMISSION_ERROR ([A-Za-z:_]+)/))
    emit.call "CHILD_ERROR #{match[1]}"
  elsif (match = stripped.match(/\A([A-Za-z:]+(?:Error|Exception)): /))
    emit.call "TEST_EXCEPTION #{match[1]}"
  elsif stripped.match?(/\A(?:Expected|Actual):\s*(?:[0-9]+|nil|true|false|\"(?:noop|queued|sent|failed|superseded)\")\s*\z/)
    emit.call stripped
  elsif (match = stripped.match(/\A(?:Error|Failure):\z/))
    emit.call "TEST_DIAGNOSTIC #{match[0]}"
  end
end
%w[NameError NoMethodError ArgumentError SyntaxError Timeout::Error ActiveRecord::StatementInvalid ActiveRecord::RecordInvalid].each do |category|
  emit.call "TEST_CATEGORY #{category}" if output.include?(category)
end
exit(status.exitstatus || 1)
