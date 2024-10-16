namespace :app_settings do
  task dump: :environment do
    AppSettings.keys.each do |k|

    v = eval("AppSettings.#{k}")
    v_is_boolean = v.class.to_s == 'String' && (v.strip == 'true' || v.strip == 'false')
    v_is_array = v.class.to_s == 'Array'

    if v_is_boolean
      puts "AppSettings.#{k} = #{v}\n\n"
    elsif v_is_array
      v.each do |i|
        puts "AppSettings.#{k} = <<HEREDOC\n"
        puts i 
        puts "HEREDOC\n\n"
      end
    else
      puts "AppSettings.#{k} = <<HEREDOC\n"
      puts v
      puts "HEREDOC\n\n"
    end

    end
  end

  task load: :environment do
  end

end
