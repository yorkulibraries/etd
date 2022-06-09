class ThesisSubjectship < ApplicationRecord
  belongs_to :thesis
  belongs_to :loc_subject
end
