# frozen_string_literal: true

# rails db:seed
LocSubject.load_from_file('lib/loc_subjects.txt') if (Rails.env != 'test') && LocSubject.all.count.zero?

if (Rails.env != 'test') && User.all.count.zero?
  [User::ADMIN, User::MANAGER, User::STAFF].each do |role|
    user = User.new
    user.username = role.to_s
    user.email = "#{role}@me.ca"
    user.name = "#{role} User"
    user.role = role
    user.blocked = false
    user.save
  end
end

if Rails.env.development?
  for i in 10..25
    Student.create(username: "username#{i}" , name: "name#{i}", email: "email#{i}@domain.com", created_by_id: 1, blocked: false, role: User::STUDENT, sisid: "1000000#{i}")
    GemRecord.create(studentname: "studentname #{i}", sisid: "1000000#{i}", emailaddress: "student-email#{i}@domain.com", eventtype: GemRecord::MASTERS_COMPLETED, eventdate: 45.days, examresult: GemRecord::ACCEPTED, title: "title #{i}", program: "program #{i}", superv: "superv #{i}", seqgradevent: rand(1..10), examdate: 20.days)
  end
end