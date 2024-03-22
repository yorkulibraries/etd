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

if (Rails.env == 'development') && GemRecord.all.count.zero?
  (10..19).each do |i|
    g = GemRecord.create(studentname: "studentname #{i}", sisid: "6942000#{i}",
                     emailaddress: "student-email#{i}@domain.com", eventtype: GemRecord::PHD_EXAM, eventdate: 45.days.ago.to_s, examresult: 'Accepted Pending Specified Revisions', title: "title #{i}", program: "program #{i}", superv: "superv #{i}", seqgradevent: "#{i}".to_i, examdate: Time.now)
    g.save!
  end
end
