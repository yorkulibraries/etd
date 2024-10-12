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
  (1..2).each do |i|
    g = GemRecord.create(
      studentname: "studentname #{i}",
      sisid: "69420000#{i}",
      emailaddress: "student-email#{i}@domain.com",
      eventtype: GemRecord::PHD_EXAM,
      eventdate: 45.days.ago.to_s,
      examresult: 'Accepted Pending Specified Revisions',
      title: "title #{i}",
      program: "GS PHD MATS - Faculty of Graduate Studies, Ph.D., Mathematics & Statistic",
      superv: "superv #{i}", 
      seqgradevent: "#{i}".to_i,
      examdate: 45.days.ago.to_s
    )
    g.save!

    cm = CommitteeMember.new
    cm.gem_record = g
    cm.first_name = "John #{i}"
    cm.last_name = "Doe"
    cm.role = CommitteeMember::CHAIR
    cm.save

    cm = CommitteeMember.new
    cm.gem_record = g
    cm.first_name = "Jane #{i}"
    cm.last_name = "Doe"
    cm.role = CommitteeMember::COMMITTEE_MEMBER
    cm.save
  end

  (3..4).each do |i|
    g = GemRecord.create(
      studentname: "studentname #{i}",
      sisid: "69420000#{i}",
      emailaddress: "student-email#{i}@domain.com",
      eventtype: GemRecord::MASTERS_EXAM,
      eventdate: 45.days.ago.to_s,
      examresult: 'Accepted Pending Specified Revisions',
      title: "title #{i}",
      program: "GS MSC KAHS - Faculty Of Graduate Studies, M.Sc., Kinesiology & Health Science",
      superv: "superv #{i}", 
      seqgradevent: "#{i}".to_i,
      examdate: 45.days.ago.to_s
    )
    g.save!

    cm = CommitteeMember.new
    cm.gem_record = g
    cm.first_name = "John #{i}"
    cm.last_name = "Doe"
    cm.role = CommitteeMember::CHAIR
    cm.save

    cm = CommitteeMember.new
    cm.gem_record = g
    cm.first_name = "Jane #{i}"
    cm.last_name = "Doe"
    cm.role = CommitteeMember::COMMITTEE_MEMBER
    cm.save
  end
end

# Set the AppSettings values
AppSettings.student_review_license_yorkspace = <<HEREDOC
YorkSpace Non-Exclusive Distribution Licence
HEREDOC

AppSettings.student_review_license_etd = <<HEREDOC
YorkU ETD Licence
HEREDOC
