# frozen_string_literal: true

class Ability
  include CanCan::Ability

  def initialize(user)
    user ||= User.new

    case user.role
    when User::ADMIN, User::MANAGER
      can :manage, :all

      can :login_as, :student
      can :show, :home
      can :embargo, :student

    when User::STAFF
      can :read, GemRecord
      can %i[create update read update_status audit_trail block unblock assign unassign],
          [Student, Thesis, CommitteeMember]
      can :manage, Document
      can %i[read approve decline], EmbargoRequest

      can :login_as, :student
      can :show, :home
    when User::STUDENT
      can :read, [:student, Student]

      can :manage, Document do |document|
        if document.embargo_request.present?
          document.embargo_request.thesis.student_id == user.id && document.embargo_request.draft?
        else
          document.thesis.student_id == user.id &&
            [Thesis::OPEN, Thesis::RETURNED].include?(document.thesis.status)
        end
      end

      can :read, Document do |document|
        document.embargo_request.present? && document.embargo_request.thesis.student_id == user.id
      end

      can :update, EmbargoRequest do |request|
        request.thesis.student_id == user.id && request.draft?
      end

      can :read, EmbargoRequest do |request|
        request.thesis.student_id == user.id
      end

      can :submit, EmbargoRequest do |request|
        request.thesis.student_id == user.id && request.draft?
      end

      can :create, EmbargoRequest do |request|
        request.thesis.student_id == user.id
      end

      can [:edit, :update, :read, :submit_for_review, :organize_student_information, :accept_licences], Thesis do |thesis|
        (thesis.status == Thesis::OPEN || thesis.status == Thesis::RETURNED) && thesis.student_id == user.id
      end

      can :show, Thesis do |thesis|
        thesis.student_id == user.id
      end

      can :show, :home

    end
  end
end
