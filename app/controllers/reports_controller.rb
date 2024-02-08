# frozen_string_literal: true

class ReportsController < ApplicationController
  skip_authorization_check

  def dashboard
    @theses_count = Thesis.count
    @theses_open_count = Thesis.open.count
    @theses_under_review_count = Thesis.under_review.count
    @theses_rejected_count = Thesis.rejected.without_embargo.count
    @theses_accepted_count = Thesis.accepted.without_embargo.count
    @theses_published_count = Thesis.published.without_embargo.count
    @theses_embargoed_count = Thesis.with_embargo.count

    @total_students = Student.count

    @total_gem_records = GemRecord.count

    @total_loc_subjects = LocSubject.count

    @total_users = User.count
  end

  def by_status
    @status = params[:status] || Thesis::UNDER_REVIEW
    @date = params[:date] || nil
    @sort = params[:sort] || 'published_date'

    @null_date_count = Thesis.where(status: @status).where(published_date: nil).count
    @published_date_counts = Thesis.where(status: @status).where.not(published_date: nil).group(:published_date).count('published_date')

    @theses = if @status == 'embargoed'
                Thesis.joins(:student).with_embargo
              else
                Thesis.joins(:student).where(status: @status).where(published_date: @date).order("#{@sort} #{sort_direction}")
              end

    respond_to do |format|
      format.html
      format.js
      format.xlsx do
        response.headers['Content-Disposition'] = 'attachment; filename="theses_report.xlsx"'
      end
    end
  end

  def review_thesis
    @thesis = Thesis.find(params[:id])
    theses = Thesis.where(status: @thesis.status).order(:published_date).select(:id).collect(&:id)
    @status = @thesis.status
    current = theses.index(@thesis.id)

    @next_id = current == theses.last ? current : theses[current + 1]
    @prev_id = current.zero? ? 0 : theses[current - 1]
  end

  def under_review_theses
    if params[:id]
      @thesis = Thesis.find(params[:id])
      theses = Thesis.under_review.select(:id).collect(&:id)

      current = theses.index(@thesis.id)

      @next_id = current == theses.last ? current : theses[current + 1]
      @prev_id = current.zero? ? 0 : theses[current - 1]

    else
      @theses = Thesis.under_review
    end
  end

  def published_theses
    @theses = Thesis.published
  end

  private

  def sort_column
    params[:sort].nil? ? params[:sort] : 'published_date'
  end

  def sort_direction
    %w[asc desc].include?(params[:direction]) ? params[:direction] : 'asc'
  end
end
