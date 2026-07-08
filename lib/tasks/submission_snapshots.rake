# frozen_string_literal: true

namespace :submission_snapshots do
  desc 'Create initial submitted-file snapshots for existing non-open theses without snapshots'
  task backfill: :environment do
    scope = Thesis.where.not(status: Thesis::OPEN)
                  .left_outer_joins(:submission_versions)
                  .where(thesis_submission_versions: { id: nil })

    created = 0
    skipped = 0

    scope.find_each do |thesis|
      if thesis.documents.not_deleted.empty?
        skipped += 1
        next
      end

      Thesis.transaction do
        thesis.create_submission_snapshot!(thesis.student)
      end
      created += 1
      puts "Created submission snapshot for thesis #{thesis.id}"
    rescue StandardError => e
      skipped += 1
      warn "Skipped thesis #{thesis.id}: #{e.class} #{e.message}"
    end

    puts "Created #{created} submission snapshots. Skipped #{skipped} theses."
  end
end
