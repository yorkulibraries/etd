namespace :etd25 do
  task :rename_files => :environment do |t|
    Thesis.open.each do |t|
      t.documents.not_deleted.each do |d|
        correct_usage(d)
      end
    end
    Thesis.returned.each do |t|
      t.documents.not_deleted.each do |d|
        correct_usage(d)
      end
    end
    Thesis.under_review.each do |t|
      t.documents.not_deleted.each do |d|
        correct_usage(d)
      end
    end
    Thesis.accepted.each do |t|
      t.documents.not_deleted.each do |d|
        correct_usage(d)
      end
    end


    Thesis.open.each do |t|
      t.documents.not_deleted.each do |d|
        rename(d)
      end
    end
    Thesis.returned.each do |t|
      t.documents.not_deleted.each do |d|
        rename(d)
      end
    end
    Thesis.under_review.each do |t|
      t.documents.not_deleted.each do |d|
        rename(d)
      end
    end
    Thesis.accepted.each do |t|
      t.documents.not_deleted.each do |d|
        rename(d)
      end
    end
  end

  def correct_usage(d)
    u = d.user_id
    t = d.thesis_id
    if d.file.path.match?(/embargo/i)
      puts "Embargo - setting document usage to embargo u:#{u} t:#{t} path:#{d.file.path}"
      d.usage = 'embargo'
      d.save! validate: false
    end
    if d.file.path.match?(/licence/i)
      puts "Licence - setting document usage to licence u:#{u} t:#{t} path:#{d.file.path}"
      d.usage = 'licence'
      d.save! validate: false
    end
    if d.file.path.match?(/license/i)
      puts "Licence - setting document usage to licence u:#{u} t:#{t} path:#{d.file.path}"
      d.usage = 'licence'
      d.save! validate: false
    end
  end

  def rename(d)
    puts d.file.path + "\n"
    d.file = File.open(d.file.path)
    d.save! validate: false
    d.name = File.basename(d.file.path)
    d.save! validate: false
    puts d.file.path + "\n\n"
  end
end
