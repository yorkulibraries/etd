# frozen_string_literal: true

##
# Function to load gem records from a text file, delimited by __ETD_COLSEP__
##
class LoadGemRecords
  def load_stdin
    count = 0

    $stdin.each_line do |line|
      tokens = line.split('__ETD_COLSEP__')
      seqgradevent = tokens[0].strip

      if GemRecord.find_by_seqgradevent(seqgradevent)

      # Duplicates found. Skipping record.
      # STDOUT.puts("Duplicate found: " + seqgradevent.to_s)

      else
        gr = GemRecord.new
        gr.seqgradevent = seqgradevent
        gr.studentname = tokens[1].strip
        gr.sisid = tokens[2].strip
        gr.emailaddress = tokens[3].strip
        gr.eventtype = tokens[4].strip
        gr.eventdate = tokens[5].strip
        gr.examresult = tokens[6].strip
        gr.title = tokens[7].strip
        gr.program = tokens[8].strip
        gr.superv = tokens[9].strip
        gr.examdate = tokens[10].strip

        if gr.save!(validate: false)

          # Inserting Record.
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
