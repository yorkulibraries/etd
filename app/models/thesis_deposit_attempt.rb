# frozen_string_literal: true

# One try at sending one thesis to YorkSpace, saved before the send starts.
#
# open_thesis_id is set to the thesis id while the send is in progress (SENDING) or its result is
# uncertain (NEEDS_CHECKING). Its unique index means a second send of that thesis cannot start until
# someone checks YorkSpace and resolves the earlier one (rake dspace:attempts:resolve).
class ThesisDepositAttempt < ApplicationRecord
  SENDING = 'sending'
  SENT = 'sent'                    # in YorkSpace and marked published
  FAILED = 'failed'                # YorkSpace kept nothing; a later export may try again
  NEEDS_CHECKING = 'needs_checking' # may be in YorkSpace; held back until checked
  HELD = 'held'                    # not sent, because an earlier send of this thesis needs checking
  STATES = [SENDING, SENT, FAILED, NEEDS_CHECKING, HELD].freeze

  # Licence handoff problems that staff should hear about.
  LICENCE_PROBLEMS = %w[no_item_id error].freeze

  # The tables use utf8mb3, which cannot store 4-byte characters such as emoji.
  NOT_STORABLE = /[^\u0000-\uFFFF]/

  def self.storable(text)
    text.to_s.scrub('?').gsub(NOT_STORABLE, '?')
  end

  belongs_to :thesis
  belongs_to :export_log

  validates :state, inclusion: { in: STATES }

  scope :unresolved, -> { where.not(open_thesis_id: nil) }
  # SENDING is included: a send whose result could not be recorded stays SENDING and held back.
  scope :needing_attention, -> { where(state: [SENDING, NEEDS_CHECKING, HELD]) }

  # Returns the new attempt, or nil when this thesis already has an unresolved send.
  def self.claim(thesis:, export_log:)
    create!(thesis:, export_log:, state: SENDING, open_thesis_id: thesis.id)
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def self.hold!(thesis:, export_log:)
    create!(thesis:, export_log:, state: HELD,
            error_message: 'Not sent: an earlier send of this thesis still needs checking in YorkSpace.')
  end

  def sent!
    change!(state: SENT, open_thesis_id: nil)
  end

  def failed!(message)
    change!(state: FAILED, open_thesis_id: nil, error_message: self.class.storable(message))
  end

  # Keeps open_thesis_id, so the thesis is not sent again until someone checks YorkSpace.
  def needs_checking!(message, sword_location: nil)
    change!(state: NEEDS_CHECKING, error_message: self.class.storable(message),
            sword_location: sword_location || self.sword_location)
  end

  private

  # If the save fails, go back to what the database holds, so a hold cleared only in memory can never
  # be saved by a later fallback update.
  def change!(attributes)
    update!(attributes)
  rescue StandardError
    reload
    raise
  end
end
