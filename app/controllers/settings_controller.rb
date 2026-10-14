# frozen_string_literal: true

class SettingsController < ApplicationController
  authorize_resource AppSettings

  def edit; end

  def dspace; end

  def update
    settings = params[:app_settings]

    validity_days = settings[:invitation_validity_days]
    if validity_days.present? && !validity_days.match?(/\A[1-9]\d*\z/)
      redirect_to edit_settings_path, alert: 'Invitation validity must be a positive number of calendar days.'
      return
    end

    settings.each do |key, value|
      AppSettings.send("#{key}=", value)
    end

    case params[:return_to]
    when 'dspace'
      redirect_to dspace_settings_path, notice: 'Saved DSpace Settings'
    else
      redirect_to edit_settings_path
    end
  end
end
