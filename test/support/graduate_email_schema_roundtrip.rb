# frozen_string_literal: true
# F03 F04 F18 F22: destructive schema E2E gate, only via guarded exec.
require 'digest'
root = Rails.root.to_s
config = ActiveRecord::Base.connection_db_config.configuration_hash
expected = ENV['DB_ADAPTER'] == 'sqlite3' ? "#{root}/tmp/graduate-email-storage_test.sqlite3" : 'etd_graduate_email_test'
raise 'Schema gate requires guarded disposable connection' unless ENV['GRADUATE_EMAIL_PROJECT_ROOT'] == root &&
  ENV['DATABASE_URL'] == ENV['TEST_DATABASE_URL'] && config[:adapter] == ENV['DB_ADAPTER'] && config[:database] == expected
c = ActiveRecord::Base.connection
source = ARGV.fetch(0)
raise 'Unknown schema source' unless %w[generated tracked].include?(source)
path = source == 'generated' ? ENV.fetch('SCHEMA') : Rails.root.join('db/schema.rb').to_s
# Literal boundary cases catch double decoding, quote damage and accidental edits
# inside SQL string literals. This table is disposable and never enters db/schema.
values = ["quote'boundary", 'back\\slash', "_utf8mb4'literal", 'double"quote', "line\nbreak"]
if source == 'generated'
  c.create_table(:graduate_schema_literals, force: true) do |t|
    t.string :value
    t.string "_utf8mb4'identifier'"
  end
  expression = "value IN (#{values.map { |value| c.quote(value) }.join(',')}) AND #{c.quote_column_name("_utf8mb4'identifier'")} IS NULL"
  c.add_check_constraint(:graduate_schema_literals, expression, name: 'graduate_schema_literal_boundary')
  File.open(path, 'w') { |file| ActiveRecord::SchemaDumper.dump(c, file) }
end
raise 'Server-specific default collation in schema' if File.read(path).include?('utf8mb4_0900_ai_ci')
checksum = Digest::SHA256.file(path).hexdigest
begin
  c.disable_referential_integrity { load path }
  raise 'Schema source edited' unless checksum == Digest::SHA256.file(path).hexdigest
  if source == 'generated'
    values.each { |value| c.execute("INSERT INTO graduate_schema_literals (value) VALUES (#{c.quote(value)})") }
    begin
      c.execute("INSERT INTO graduate_schema_literals (value) VALUES ('invalid')")
      raise 'Literal CHECK absent'
    rescue ActiveRecord::StatementInvalid
      # Actual database rejection required.
    end
  end
  # Normal test helper maintenance runs in a new process after this script.
  File.write(Rails.root.join("tmp/graduate-email/#{ENV.fetch('DB_ADAPTER')}-#{source}-roundtrip.txt"), "SCHEMA_ROUNDTRIP PASS #{source} unedited literals=#{source == 'generated' ? values.length : 0}\n")
ensure
  c.drop_table(:graduate_schema_literals, if_exists: true)
end
