require 'test_helper'

class AppSettingsTest < ActiveSupport::TestCase 
   
   # This test is more to ensure app_settings model exists than for student_begin_submission 
   # because var can hold any setting with value set. Validation can be explored via another test.
   should "create a new setting with 'student_begin_submission'" do
      setting = FactoryGirl.create(:app_settings, var: "student_begin_submission")
      setting.value = "This is begin, first step"
      setting.save
      assert_equal "student_begin_submission", setting.var
      assert_equal "This is begin, first step", setting.value
   end

   should 'store the DSpace REST API URL' do
      AppSettings.dspace_rest_api_url = 'https://repository.example/server/api'

      assert_equal 'https://repository.example/server/api', AppSettings.dspace_rest_api_url
   end

end
