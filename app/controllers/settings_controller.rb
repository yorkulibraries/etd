class SettingsController < ApplicationController
  authorize_resource AppSettings

  def edit; end

  def dspace; end

  def update
    settings = params[:app_settings]

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
