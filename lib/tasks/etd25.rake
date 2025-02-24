namespace :etd25 do
  task :rename_files => :environment do |t|
    Thesis.open.each do |t|
      t.documents.not_deleted.each do |d|
        puts d.file.path + "\n"
        d.file = File.open(d.file.path)
        d.save! validate: false
        d.name = File.basename(d.file.path)
        d.save! validate: false
        puts d.file.path + "\n\n"
      end
    end
    Thesis.returned.each do |t|
      t.documents.not_deleted.each do |d|
        puts d.file.path + "\n"
        d.file = File.open(d.file.path)
        d.save! validate: false
        d.name = File.basename(d.file.path)
        d.save! validate: false
        puts d.file.path + "\n\n"
      end
    end
    Thesis.under_review.each do |t|
      t.documents.not_deleted.each do |d|
        puts d.file.path + "\n"
        d.file = File.open(d.file.path)
        d.save! validate: false
        d.name = File.basename(d.file.path)
        d.save! validate: false
        puts d.file.path + "\n\n"
      end
    end
    Thesis.accepted.each do |t|
      t.documents.not_deleted.each do |d|
        puts d.file.path + "\n"
        d.file = File.open(d.file.path)
        d.save! validate: false
        d.name = File.basename(d.file.path)
        d.save! validate: false
        puts d.file.path + "\n\n"
      end
    end
  end
end
