module ApplicationHelper
  def app_version
    '1.3.1'
  end

  def is_controller_and_action?(controller, action)
    controller_name == controller && action_name == action
  end

  def controller_name
    controller.controller_name
  end

  def action_name
    controller.action_name
  end

  def block_thesis_changes?(thesis)
    return false if thesis.nil?

    if @current_user.role == User::STUDENT && (thesis.status != Thesis::OPEN && thesis.status != Thesis::RETURNED)
      true
    else
      false
    end
  end

  def auditable_link(auditable)
    if auditable.is_a?(Thesis)
      student_thesis_path(auditable.student.id, auditable.id)
    elsif auditable.is_a?(User)
      users_path
    elsif auditable.is_a?(Student)
      student_path(auditable.id)
    elsif auditable.is_a?(Document)
      student_thesis_path(auditable.thesis.student.id, auditable.id)
    elsif auditable.is_a?(GemRecord)
      gem_record_path(auditable.id)
    else
      ''
    end
  end

  def link_to_add_fields(name, f, association)
    new_object = f.object.send(association).klass.new
    id = new_object.object_id
    fields = f.fields_for(association, new_object, child_index: id) do |builder|
      render(association.to_s.singularize + '_fields', f: builder)
    end
    link_to(name, '#', class: 'add_fields', data: { id: id, fields: fields.gsub("\n", '') })
  end
end
