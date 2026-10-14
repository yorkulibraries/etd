# frozen_string_literal: true

require Rails.root.join('lib/etd/dspace_rest_client.rb')
require Rails.root.join('lib/etd/ensure_license_bundle.rb')

class DspaceLicenseBundleJob < ApplicationJob
  queue_as 'dspace_licenses'

  def perform(dspace_deposit_id)
    deposit = DspaceDeposit.find_by(id: dspace_deposit_id)
    return unless deposit

    ETD::LicenseItemLock.synchronize(deposit.item_uuid) do
      deposit.reload
      return if [DspaceDeposit::COMPLETE, DspaceDeposit::REVIEW_REQUIRED].include?(deposit.license_status)
      return if deposit.license_retry_at && deposit.license_retry_at > Time.current
      if deposit.license_attempts >= 5
        deposit.update!(license_status: DspaceDeposit::REVIEW_REQUIRED, license_retry_at: nil,
                        last_error: 'Automatic licence attempts exhausted; inspect remote state before retrying')
        return
      end

      sync(deposit)
    end
  rescue ETD::LicenseItemLock::Busy
    # The database record remains available to the recovery worker.
    nil
  end

  private

  def sync(deposit)
    deposit.update!(license_status: DspaceDeposit::RUNNING, last_error: nil,
                    license_attempts: deposit.license_attempts + 1)
    ETD::EnsureLicenseBundle.new(client: dspace_client).call(item_uuid: deposit.item_uuid)
    deposit.update!(
      license_status: DspaceDeposit::COMPLETE,
      license_synced_at: Time.current,
      license_retry_at: nil,
      last_error: nil
    )
  rescue ETD::EnsureLicenseBundle::ConflictError, ETD::EnsureLicenseBundle::PayloadError => e
    deposit&.update!(license_status: DspaceDeposit::REVIEW_REQUIRED, last_error: e.message)
  rescue StandardError => e
    terminal = deposit.license_attempts >= 5 ||
               (e.is_a?(ETD::DspaceRestClient::RequestError) && [400, 401, 403, 405, 422].include?(e.status))
    deposit.update!(license_status: terminal ? DspaceDeposit::REVIEW_REQUIRED : DspaceDeposit::FAILED,
                    license_retry_at: terminal ? nil : 5.minutes.from_now, last_error: e.message)
    raise
  end

  def dspace_client
    raise 'DSpace REST API URL is not configured' if AppSettings.dspace_rest_api_url.blank?

    ETD::DspaceRestClient.new(
      base_url: AppSettings.dspace_rest_api_url,
      username: AppSettings.dspace_live_username,
      password: AppSettings.dspace_live_password
    )
  end
end
