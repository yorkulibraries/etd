namespace :proquest_subjects do
  desc 'Loading Proquest Subjects.'

  task load: :environment do
    puts 'Loading Proquest Subjects'

    begin
      config = ActiveRecord::Base.configurations[::Rails.env]
      ActiveRecord::Base.establish_connection
      case config['adapter']
      when 'mysql', 'mysql2', 'postgresql'
        puts 'HERE'
        ActiveRecord::Base.connection.execute('TRUNCATE loc_subjects')
      when 'sqlite', 'sqlite3'
        ActiveRecord::Base.connection.execute('DELETE FROM loc_subjects')
        ActiveRecord::Base.connection.execute("DELETE FROM sqlite_sequence where name='loc_subjects'")
        ActiveRecord::Base.connection.execute('VACUUM')
      end
    end

    LocSubject.load_from_file('lib/loc_subjects.txt')
  end
end
