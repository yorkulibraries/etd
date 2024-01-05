# rails db:seed
LocSubject.load_from_file('lib/loc_subjects.txt') if Rails.env != 'test' and LocSubject.all.count == 0

if Rails.env != 'test' and User.all.count == 0
  [User::ADMIN, User::MANAGER, User::STAFF].each do |role|
    user = User.new
    user.username = "#{role}"
    user.email = "#{role}@me.ca"
    user.name = "#{role} User"
    user.role = role
    user.blocked = false
    user.save
  end
end
