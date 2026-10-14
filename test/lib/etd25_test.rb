# frozen_string_literal: true

require 'test_helper'
require 'rake'

class EtD25Test < ActiveSupport::TestCase
  setup do
    Rake::Task.define_task(:environment) unless Rake::Task.task_defined?(:environment)
    load Rails.root.join('lib/tasks/etd25.rake') unless Rake::Task.task_defined?('etd25:rename_files')
  end

  should 'leave request-bound evidence untouched by legacy filename inference' do
    document = mock('request-bound document')
    document.stubs(:embargo_request_id).returns(123)
    document.stubs(:user_id).returns(1)
    document.stubs(:thesis_id).returns(2)
    document.expects(:file).never
    document.expects(:usage=).never
    document.expects(:save!).never

    send(:correct_usage, document)
    send(:rename, document)
  end
end
