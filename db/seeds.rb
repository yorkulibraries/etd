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

10.times { |i| Student.create(username: "username#{i}" , name: "name#{i}", email: "email#{i}@domain.com", created_by_id: 1, blocked: false, role: User::STUDENT, sisid: "10000000#{i}") } if Rails.env.development?
