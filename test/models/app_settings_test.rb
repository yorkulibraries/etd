require 'test_helper'

class AppSettingsTest < ActiveSupport::TestCase 
   setup do
      AppSettings.clear_cache
   end

   should 'default invitation validity to 14 calendar days' do
      assert_equal 14, AppSettings.invitation_validity_days
   end

   should 'store invitation validity as a positive integer' do
      AppSettings.invitation_validity_days = '21'

      assert_equal 21, AppSettings.invitation_validity_days
   end

   should 'reject a non-positive invitation validity' do
      assert_raises ActiveRecord::RecordInvalid do
         AppSettings.invitation_validity_days = 0
      end
   end
   
   # This test is more to ensure app_settings model exists than for student_begin_submission 
   # because var can hold any setting with value set. Validation can be explored via another test.
   should "create a new setting with 'student_begin_submission'" do
      setting = FactoryGirl.create(:app_settings, var: "student_begin_submission")
      setting.value = "This is begin, first step"
      setting.save
      assert_equal "student_begin_submission", setting.var
      assert_equal "This is begin, first step", setting.value
   end

end
