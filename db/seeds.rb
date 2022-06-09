# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)
# admin user

if Rails.env != 'test' and LocSubject.all.count == 0
  LocSubject.load_from_file("lib/loc_subjects.txt")
end

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
