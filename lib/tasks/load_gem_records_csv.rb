# frozen_string_literal: true

##
# Function to load gem records from a CSV file
##

require 'csv'

class LoadGemRecordsCSV

  def load_gem_records(filename)
    count = 0

    converter = lambda { |header| header.downcase }
    CSV.foreach(filename, headers: true, header_converters: converter) do |row|
      seqgradevent = row['seqgradevent'].strip
      unless GemRecord.find_by_seqgradevent(seqgradevent)
        gr = GemRecord.new
        gr.seqgradevent = seqgradevent
        gr.studentname = row['studentname'].strip
        gr.sisid = row['sisid'].strip
        gr.emailaddress = row['emailaddress'].strip
        gr.eventtype = row['eventtype'].strip
        gr.eventdate = row['eventdate'].strip
        gr.examresult = row['examresult'].strip
        gr.title = row['title'].strip
        gr.program = row['program'].strip
        gr.superv = row['superv'].strip
        gr.examdate = row['examdate'].strip

        if gr.save!(validate: false)
          count += 1
        else
          warn('Error: Load Gem Records Save Failed!')
          warn("Error: #{gr.errors.inspect}")
        end
      end
    rescue StandardError => e
      warn("ERROR: #{e}")
      warn('Hint: Possible Bad File if strip nil')
    end
  end

  def load_committee_members(filename)
    count = 0

    converter = lambda { |header| header.downcase }
    CSV.foreach(filename, headers: true, header_converters: converter) do |row|
      seqgradevent = row['seqgradevent'].strip
      gr = GemRecord.find_by_seqgradevent(seqgradevent)
      cm = CommitteeMember.new
      cm.gem_record = gr
      cm.first_name = row['firstname'].strip
      cm.last_name = row['surname'].strip
      cm.role = row['role'].strip
      cm.save!
    end
  end
end
