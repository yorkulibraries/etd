# frozen_string_literal: true

##
# Function to load gem records from a text file, delimited by __ETD_COLSEP__
##

require 'csv'

class LoadGemRecordsCSV

  def load_csv(filename)
    count = 0

    filename = File.join(File.dirname(__FILE__), filename)

    CSV.foreach(filename, headers: true) do |row|
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
end
