# frozen_string_literal: true

class HomeController < ApplicationController
  before_action :authorize_controller, except: :unauthorized
  skip_authorization_check

  def index
    if current_user.is_a? Student
      redirect_to student_view_index_url
    else
      if params[:which] == 'embargo_requests'
        authorize! :view_embargo_request_queue, EmbargoRequest
        @pending_embargo_requests_count = EmbargoRequest.submitted.count
        @which = 'embargo_requests'
        @embargo_status = %w[submitted approved declined].include?(params[:status]) ? params[:status] : 'submitted'
        relation = EmbargoRequest.public_send(@embargo_status).includes(thesis: :student)
        @embargo_requests = if @embargo_status == 'submitted'
                              relation.order(submitted_at: :asc)
                            else
                              relation.order(decided_at: :desc)
                            end
        return render :index
      end

      @pending_embargo_requests_count = EmbargoRequest.submitted.count if can?(:view_embargo_request_queue, EmbargoRequest)

      case params[:which]
      when 'mine'
        @theses = Thesis.assigned_to_user(current_user).order('updated_at desc')
        @which = params[:which]
      when Thesis::UNDER_REVIEW
        @theses = Thesis.under_review.order('updated_at desc')
        @which = params[:which]
      when Thesis::ACCEPTED
        @theses = Thesis.accepted.order('updated_at desc')
        @which = params[:which]
      else
        @theses = Thesis.open_or_returned.order('updated_at desc')
        @which = Thesis::OPEN
      end
      render :index
    end
  end

  def unauthorized
    render layout: 'simple'
  end

  private

  def authorize_controller
    authorize! :show, :home
  end
end
