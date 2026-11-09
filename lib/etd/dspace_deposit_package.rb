# frozen_string_literal: true

require 'sword2ruby'

module ETD
  # The one definition of what a thesis deposit sends to YorkSpace: the metadata record and the files.
  # Both the website export (DspaceExportJob) and the server script (rake dspace:export) use it,
  # so the two routes cannot drift apart.
  module DspaceDepositPackage
    # Characters seen in pasted abstracts that break the SWORD XML. Line breaks and tabs are kept.
    CONTROL_CHARACTERS = "\u0002\u000B\u000C\u000E\u000F"
    RIGHTS = 'Author owns copyright, except where explicitly noted. ' \
             'Please contact the author directly with licensing requests.'

    module_function

    def entry(thesis)
      entry = Atom::Entry.new
      add = ->(name, value) { entry.add_dublin_core_extension!(name, value) unless value.blank? }

      add.call('title', thesis.title)
      add.call('creator', thesis.author)
      supervisors(thesis.supervisor).each { |supervisor| add.call('supervisor', supervisor) }
      thesis.loc_subjects.each { |subject| add.call('subject', subject.name) }
      thesis.subject_keywords.each { |keyword| add.call('relationSubjectKeywords', keyword) }
      add.call('abstract', thesis.abstract&.delete(CONTROL_CHARACTERS))
      add.call('language', language_to_iso(thesis.language))
      add.call('name', thesis.degree_name_full)
      add.call('level', thesis.degree_level)
      add.call('discipline', short_program_name(thesis.program))
      add.call('issued', Date.current.strftime('%Y-%m-%d'))
      copyright = thesis.exam_date&.strftime('%Y-%m-%d')
      add.call('dateCopyrighted', copyright)
      add.call('date.copyright', copyright)
      add.call('type', 'Electronic Thesis or Dissertation')
      add.call('rights', RIGHTS)
      entry
    end

    # Main thesis file(s) first, then supplemental files. Never licence forms, embargo evidence,
    # modification requests or files attached to an embargo request.
    def files(thesis, primary_only: false)
      return [] if thesis.nil?

      documents = thesis.documents.not_deleted.where(usage: Document.usages[:thesis], embargo_request_id: nil)
      paths = documents.where(supplemental: false).map { |document| document.file.path }
      paths += documents.where(supplemental: true).map { |document| document.file.path } unless primary_only
      paths
    end

    def supervisors(value)
      value.to_s.split('/').map(&:strip).reject(&:empty?)
    end

    def language_to_iso(language)
      case language.to_s.downcase
      when 'en', 'english', 'eng' then 'en'
      when 'fr', 'french', 'fra' then 'fr'
      else 'other'
      end
    end

    def short_program_name(program)
      program.is_a?(String) ? program.split('.,').last.to_s.strip : program
    end
  end
end
