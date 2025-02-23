namespace :etd25 do
  task :rename_files => :environment do |t|
    Thesis.open.each do |t|
      t.documents.each do |d|
        puts d.file.path + "\n"
        f = File.open(d.file.path)
        d.file = f
        d.save!
        puts d.file.path + "\n\n"
      end
    end
    Thesis.returned.each do |t|
      t.documents.each do |d|
        puts d.file.path + "\n"
        f = File.open(d.file.path)
        d.file = f
        d.save!
        puts d.file.path + "\n\n"
      end
    end
    Thesis.under_review.each do |t|
      t.documents.each do |d|
        puts d.file.path + "\n"
        f = File.open(d.file.path)
        d.file = f
        d.save!
        puts d.file.path + "\n\n"
      end
    end
  end
end
