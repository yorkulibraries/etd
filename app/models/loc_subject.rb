class LocSubject < ApplicationRecord  

  validates_presence_of :name, :category

  def LocSubject.load_from_file(file)
    file = File.open(file)

    category = "unknown"

    ApplicationRecord.transaction do

      file.each do |line|
        begin
          if line.starts_with? ">"
            category = line[1, line.length]
          end

          subject = LocSubject.new
          subject.name = line.strip
          subject.category = category.strip
          subject.save! unless line.starts_with? ">" # don't save if processing category

        rescue Exception => e
          puts "Error: #{e.message}"
        end
      end
    end
  end
end
