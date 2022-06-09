module ThesesHelper

  def format(field, simple_format = false, message = "Not filled in...")
    # If field is blank, print out blank message
    if field.blank?
      content_tag(:span, message, class: "empty-field")
    else
      if field.is_a? Date
        field.strftime("%B %d, %Y")
      else
        simple_format ? simple_format(field) : field
      end
    end
  end

  def read_only_if_student(field)
    if current_user.role == User::STUDENT && Student::IMMUTABLE_THESIS_FIELDS.include?(field)
      true
    else
      false
    end
  end

  def can_assign_to_anyone?
    if current_user.role == User::ADMIN || current_user.role == User::MANAGER
      true
    else
      false
    end
  end


  def publish_on_dates(start = 1.year)
    dates = Array.new
    ((Date.today - start)..(Date.today + 4.years)).each do |date|
      if (date.month == 11 || date.month == 7 || date.month == 3) && date.day == 1
        dates.push([date.strftime("%b %e, %Y"), date.strftime("%Y-%m-%d")])
      end
    end

    dates
  end
end
