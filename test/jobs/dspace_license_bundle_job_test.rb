# frozen_string_literal: true

require 'test_helper'
require 'etd/dspace_rest_client'
require 'etd/license_files'
require_relative '../support/sqlite_license_lock'

class DspaceLicenseBundleJobTest < ActiveSupport::TestCase
  include SqliteLicenseLock
  class CompleteBundleClient
    def bundles(_item_uuid)
      [{ 'uuid' => '11111111-1111-4111-8111-111111111111', 'name' => 'LICENSE' }]
    end

    def bitstreams(_bundle_uuid)
      ETD::LicenseFiles.canonical.map do |file|
        {
          'uuid' => SecureRandom.uuid,
          'name' => file.fetch(:name),
          'sizeBytes' => file.fetch(:size),
          'checkSum' => {
            'checkSumAlgorithm' => 'MD5',
            'value' => file.fetch(:md5)
          }
        }
      end
    end
  end

  class ConflictingBundleClient < CompleteBundleClient
    def bitstreams(bundle_uuid)
      super.tap do |bitstreams|
        bitstreams.first.fetch('checkSum')['value'] = Digest::MD5.hexdigest('different bytes')
      end
    end
  end

  class FailingClient
    def bundles(_item_uuid)
      raise ETD::DspaceRestClient::RequestError, 'repository unavailable'
    end
  end

  setup do
    AppSettings.dspace_rest_api_url = 'https://repository.example/server/api'
    AppSettings.dspace_live_username = 'depositor@example.org'
    AppSettings.dspace_live_password = 'secret password'
    @deposit = DspaceDeposit.create!(
      thesis: create(:thesis),
      export_log: create(:export_log),
      item_uuid: '22222222-2222-4222-8222-222222222222'
    )
  end

  should 'mark an already complete item as synchronised' do
    ETD::DspaceRestClient.stubs(:new).returns(CompleteBundleClient.new)

    DspaceLicenseBundleJob.perform_now(@deposit.id)

    @deposit.reload
    assert_equal DspaceDeposit::COMPLETE, @deposit.license_status
    assert_not_nil @deposit.license_synced_at
    assert_nil @deposit.last_error
  end

  should 'stop retrying and flag an item that needs manual review' do
    ETD::DspaceRestClient.stubs(:new).returns(ConflictingBundleClient.new)

    DspaceLicenseBundleJob.perform_now(@deposit.id)

    @deposit.reload
    assert_equal DspaceDeposit::REVIEW_REQUIRED, @deposit.license_status
    assert_match(/license\.txt/, @deposit.last_error)
    assert_nil @deposit.license_synced_at
  end

  should 'persist a retryable failure and re-raise the transport error' do
    ETD::DspaceRestClient.stubs(:new).returns(FailingClient.new)

    error = assert_raises(ETD::DspaceRestClient::RequestError) do
      DspaceLicenseBundleJob.perform_now(@deposit.id)
    end

    assert_equal 'repository unavailable', error.message
    @deposit.reload
    assert_equal DspaceDeposit::FAILED, @deposit.license_status
    assert_equal 'repository unavailable', @deposit.last_error
    assert_nil @deposit.license_synced_at
    assert_equal 1, @deposit.license_attempts
    assert_operator @deposit.license_retry_at, :>, Time.current
  end

  should 'recover a due failure without repeating the SWORD deposit' do
    @deposit.update!(license_status: DspaceDeposit::FAILED, license_attempts: 1, license_retry_at: 1.minute.ago)
    ETD::DspaceRestClient.stubs(:new).returns(CompleteBundleClient.new)
    ETD::Exporter.expects(:new).never
    DspaceLicenseBundleJob.perform_now(@deposit.id)
    assert_equal DspaceDeposit::COMPLETE, @deposit.reload.license_status
    assert_equal 2, @deposit.license_attempts
    assert_nil @deposit.license_retry_at
  end

  should 'recover interrupted work after its previous worker has gone away' do
    @deposit.update!(license_status: DspaceDeposit::RUNNING, license_attempts: 1)
    ETD::DspaceRestClient.stubs(:new).returns(CompleteBundleClient.new)
    DspaceLicenseBundleJob.perform_now(@deposit.id)
    assert_equal DspaceDeposit::COMPLETE, @deposit.reload.license_status
  end

  should 'leave review records and retries that are not due untouched' do
    ETD::DspaceRestClient.expects(:new).never
    @deposit.update!(license_status: DspaceDeposit::REVIEW_REQUIRED)
    DspaceLicenseBundleJob.perform_now(@deposit.id)
    assert_equal DspaceDeposit::REVIEW_REQUIRED, @deposit.reload.license_status
    @deposit.update!(license_status: DspaceDeposit::FAILED, license_retry_at: 5.minutes.from_now)
    DspaceLicenseBundleJob.perform_now(@deposit.id)
    assert_equal 0, @deposit.reload.license_attempts
  end

  should 'stop automatic recovery after five failures' do
    @deposit.update!(license_attempts: 4)
    ETD::DspaceRestClient.stubs(:new).returns(FailingClient.new)
    assert_raises(ETD::DspaceRestClient::RequestError) { DspaceLicenseBundleJob.perform_now(@deposit.id) }
    assert_equal DspaceDeposit::REVIEW_REQUIRED, @deposit.reload.license_status
    assert_nil @deposit.license_retry_at
  end

  should 'recover persisted work through the recovery rake task' do
    require 'rake'
    # Loading all tasks here appends a second action to the already-loaded exporter.
    load Rails.root.join('lib/tasks/dspace_licenses.rake') unless Rake::Task.task_defined?('dspace:licenses:recover')
    Rake::Task.define_task(:environment) unless Rake::Task.task_defined?(:environment)
    ETD::DspaceRestClient.stubs(:new).returns(CompleteBundleClient.new)
    Rake::Task['dspace:licenses:recover'].reenable
    Rake::Task['dspace:licenses:recover'].invoke
    assert_equal DspaceDeposit::COMPLETE, @deposit.reload.license_status
  end
end
