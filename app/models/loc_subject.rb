# frozen_string_literal: true

class LocSubject < ApplicationRecord
  validates_presence_of :name, :category

  def self.load_from_file(file)
    file = File.open(file)

    category = 'unknown'

    ApplicationRecord.transaction do
      file.each do |line|
        category = line[1, line.length] if line.starts_with? '>'

        subject = LocSubject.new
        subject.name = line.strip
        subject.category = category.strip
        subject.save! unless line.starts_with? '>' # don't save if processing category
      rescue Exception => e
        puts "Error: #{e.message}"
      end
    end
  end
end
