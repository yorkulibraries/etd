# frozen_string_literal: true

require 'test_helper'

class DspaceExportJobTest < ActiveSupport::TestCase
  should 'preserve abstract paragraphs and PDF line wraps in serialized export metadata' do
    abstract = "First paragraph with an underlying\ndistribution.\n\n\tSecond paragraph with CO₂ & <research>."
    thesis = build(:thesis, abstract: abstract)

    xml = DspaceExportJob.new.thesis_to_atom_entry(thesis).to_s
    exported = REXML::Document.new(xml).root.elements.to_a.find { |element| element.name == 'abstract' }

    assert_equal abstract, exported.text
    assert_equal abstract, thesis.abstract
  end

  should 'export comma- and semicolon-separated keywords with capitalized first words' do
    thesis = build(:thesis, keywords: 'aeronomy, already Capitalized; “design”')

    values = DspaceExportJob.new.thesis_to_atom_entry(thesis).extensions.to_a
                    .select { |extension| extension.name == 'relationSubjectKeywords' }
                    .map(&:text)

    assert_equal ['Aeronomy', 'Already Capitalized', '“Design”'], values
  end
end
