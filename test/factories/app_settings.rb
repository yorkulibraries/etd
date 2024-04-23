FactoryGirl.define do
   factory :app_settings do
     var { "example_setting_name" }
     value { "example_value" }
     thing_id { nil }
     thing_type { nil }

   end
 end