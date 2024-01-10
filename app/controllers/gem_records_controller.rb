# frozen_string_literal: true

class GemRecordsController < ApplicationController
  authorize_resource

  def index
    @gem_records = GemRecord.page(params[:page])
  end

  def show
    @gem_record = GemRecord.find(params[:id])
    @student = Student.find_by_sisid(@gem_record.sisid)
  end

  private

  def gem_record_params
    params.require(:gem_record).permit(:studentname, :sisid, :emailaddress, :eventtype, :eventdate, :examresult,
                                       :title, :program, :superv)
  end
end
