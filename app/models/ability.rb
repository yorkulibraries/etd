# frozen_string_literal: true

class Ability
  include CanCan::Ability

  def initialize(user)
    user ||= User.new

    case user.role
    when User::ADMIN, User::MANAGER
      can :manage, :all
      can :view_embargo_request_queue, EmbargoRequest

      can :login_as, :student
      can :show, :home
      can :embargo, :student

    when User::STAFF
      can :read, GemRecord
      can %i[create update read update_status audit_trail block unblock assign unassign send_invite],
          [Student, Thesis, CommitteeMember]
      can :manage, Document
      can %i[read approve decline view_embargo_request_queue], EmbargoRequest

      can :login_as, :student
      can :show, :home
    when User::STUDENT
      can :read, [:student, Student]

      can :manage, Document do |document|
        thesis = document.thesis
        next false unless thesis
        next false unless thesis.student_id == user.id
        next false unless thesis.invitation_accessible?

        if document.embargo_request.present?
          document.embargo_request.draft?
        else
          [Thesis::OPEN, Thesis::RETURNED].include?(thesis.status)
        end
      end

      can :read, Document do |document|
        thesis = document.thesis
        next false unless thesis
        next false unless thesis.student_id == user.id
        next false unless thesis.invitation_accessible?

        document.embargo_request.present? || [Thesis::OPEN, Thesis::RETURNED].include?(thesis.status)
      end

      can :update, EmbargoRequest do |request|
        request.thesis.student_id == user.id &&
          request.draft? &&
          request.thesis.invitation_accessible?
      end

      can :read, EmbargoRequest do |request|
        request.thesis.student_id == user.id && request.thesis.invitation_accessible?
      end

      can :submit, EmbargoRequest do |request|
        request.thesis.student_id == user.id &&
          request.draft? &&
          request.thesis.invitation_accessible?
      end

      can :create, EmbargoRequest do |request|
        request.thesis.student_id == user.id && request.thesis.invitation_accessible?
      end

      can [:edit, :update, :read, :submit_for_review, :organize_student_information, :accept_licences], Thesis do |thesis|
        (thesis.status == Thesis::OPEN || thesis.status == Thesis::RETURNED) && thesis.student_id == user.id &&
          thesis.invitation_accessible?
      end

      can :show, Thesis do |thesis|
        thesis.student_id == user.id && thesis.invitation_accessible?
      end

      can :show, :home

    end
  end
end
