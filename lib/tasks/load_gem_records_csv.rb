# frozen_string_literal: true

##
# Function to load gem records from a CSV file
##

require 'csv'

class LoadGemRecordsCSV

  def load_gem_records(filename)
    converter = lambda { |header| header.downcase }
    CSV.foreach(filename, headers: true, header_converters: converter) do |row|
      seqgradevent = row['seqgradevent'].strip
      unless gr = GemRecord.find_by_seqgradevent(seqgradevent)
        gr = GemRecord.new
      end
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

      gr.save!
    end
  end

  def load_committee_members(filename)
    count = 0

    converter = lambda { |header| header.downcase }
    CSV.foreach(filename, headers: true, header_converters: converter) do |row|
      seqgradevent = row['seqgradevent'].strip
      sisid = row['sisid'].strip
      first_name = row['firstname'].strip
      last_name = row['surname'].strip
      role = row['role'].strip

      if gr = GemRecord.find_by_seqgradevent(seqgradevent)
        unless cm = CommitteeMember.find_by(gem_record_id: gr.id, first_name: first_name, last_name: last_name, role: role)
          cm = CommitteeMember.new
          cm.gem_record = gr
          cm.first_name = first_name
          cm.last_name = last_name
          cm.role = role
          cm.save!
        end
      end
    end
  end
end