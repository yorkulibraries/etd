# frozen_string_literal: true

##
# Function to load gem records from a CSV file
##

require 'csv'

class LoadGemRecordsCSV

  def load_gem_records(filename)
    converter = lambda { |header| header.downcase }
    CSV.foreach(filename, headers: true, header_converters: converter, skip_blanks: true) do |row|
      seqgradevent = row['seqgradevent'].strip
      unless gr = GemRecord.find_by_seqgradevent(seqgradevent)
        gr = GemRecord.new
      end
      gr.seqgradevent = seqgradevent
      gr.sisid = row['sisid'].strip unless row['sisid'].nil?
      gr.emailaddress = row['emailaddress'].strip unless row['emailaddress'].nil?
      gr.eventtype = row['eventtype'].strip unless row['eventtype'].nil?
      gr.eventdate = row['eventdate'].strip unless row['eventdate'].nil?
      gr.examresult = row['examresult'].strip unless row['examresult'].nil?
      gr.title = row['title'].strip unless row['title'].nil?
      gr.program = row['program'].strip unless row['program'].nil?
      gr.superv = row['superv'].strip unless row['superv'].nil?
      gr.examdate = row['examdate'].strip unless row['examdate'].nil?
      gr.studentname = row['surname'].strip + ', ' + row['firstname'].strip + ' ' + row['middlename'].strip unless row['surname'].nil? 

      # save without validation as GEM records may have incomplete data
      gr.save!(validate: false)
    end
  end

  def load_committee_members(filename)
    converter = lambda { |header| header.downcase }
    CSV.foreach(filename, headers: true, header_converters: converter, skip_blanks: true) do |row|
      seqgradevent = row['seqgradevent'].strip unless row['seqgradevent'].nil?
      sisid = row['sisid'].strip unless row['sisid'].nil?
      first_name = row['firstname'].strip unless row['firstname'].nil?
      last_name = row['surname'].strip unless row['surname'].nil?
      role = row['role'].strip unless row['role'].nil?

      if gr = GemRecord.find_by_seqgradevent(seqgradevent)
        unless cm = CommitteeMember.find_by(gem_record_id: gr.id, first_name: first_name, last_name: last_name, role: role)
          cm = CommitteeMember.new
          cm.gem_record = gr
          cm.first_name = first_name
          cm.last_name = last_name
          cm.role = role

          # don't throw up if validation failed, just skip the bad committee member record
          cm.save
        end
      end
    end
  end
end
