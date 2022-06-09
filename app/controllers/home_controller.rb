class HomeController < ApplicationController
  before_action :authorize_controller, except: :unauthorized
  skip_authorization_check
  
  def index
    if current_user.is_a? Student
      redirect_to student_view_index_url
    else
            
      case params[:which]
      when Thesis::UNDER_REVIEW
        @theses = Thesis.under_review
        @which = params[:which]
      when Thesis::ACCEPTED
        @theses = Thesis.accepted
        @which = params[:which]
      else
        @theses = Thesis.open + Thesis.returned
        @which = Thesis::OPEN
      end
      
      
      render :index
    end
  end  
  
  def unauthorized   
    render layout: "simple"
  end
  
  private
  def authorize_controller
      authorize! :show, :home
  end
end
