# frozen_string_literal: true

# Rails 7.0.8.1 reads INFORMATION_SCHEMA.CHECK_CLAUSE verbatim. MySQL may
# escape its quote delimiters there; SHOW CREATE TABLE supplies executable SQL.
# Read that SQL rather than unescaping arbitrary expressions or string contents.
require 'active_record/connection_adapters/mysql2_adapter'
require 'strscan'

module MysqlCheckSchemaCompatibility
  def check_constraints(table_name)
    definitions = super
    return definitions if mariadb? || definitions.empty?

    ddl = send(:create_table_info, table_name)
    definitions.map do |definition|
      name = Regexp.escape(quote_column_name(definition.name))
      match = ddl.match(/^\s*CONSTRAINT #{name} CHECK \((.*)\)(?: \/\*!\d+ NOT ENFORCED \*\/)?[,]?$/)
      raise ActiveRecord::StatementInvalid, 'Unrecognized MySQL CHECK metadata' unless match

      # The app's ASCII CHECK literals need no MySQL charset introducer. Scan
      # complete SQL tokens so introducer-like text inside literals is untouched.
      scanner = StringScanner.new(match[1])
      expression = +''
      until scanner.eos?
        if (identifier = scanner.scan(/`(?:[^`]|``)*`/m))
          expression << identifier
          next
        end
        token = scanner.scan(/(?:_utf8mb4)?'(?:[^'\\]|\\.|'')*'/m)
        if token
          expression << (token.start_with?("_utf8mb4'") && token.ascii_only? ? token.delete_prefix('_utf8mb4') : token)
        else
          expression << scanner.getch
        end
      end
      ActiveRecord::ConnectionAdapters::CheckConstraintDefinition.new(table_name, expression, definition.options)
    end
  end
end

# Keep the compatibility correction bounded to the unchanged pinned framework.
if ActiveRecord::VERSION::STRING == '7.0.8.1'
  ActiveRecord::ConnectionAdapters::Mysql2Adapter.prepend(MysqlCheckSchemaCompatibility)

  # A generated MySQL schema must also load on the supported SQLite test adapter.
  # The deliberate binary column overrides need conditional syntax.
  module MysqlPortableSchemaCompatibility
    private

    # This is an inherited local server default, not an application collation
    # contract. Omit it so schema loads inherit the target default as migrations
    # do. Explicit common email-table and binary-column collations remain.
    def format_options(options)
      options = options.except(:collation) if options[:collation] == 'utf8mb4_0900_ai_ci'
      super(options)
    end

    def schema_collation(column)
      value = super
      if column.collation == 'utf8mb4_bin'
        '(ActiveRecord::Base.connection.adapter_name == "Mysql2" ? "utf8mb4_bin" : nil)'
      else
        value
      end
    end
  end
  ActiveRecord::ConnectionAdapters::MySQL::SchemaDumper.prepend(MysqlPortableSchemaCompatibility)
end
