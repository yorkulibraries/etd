# frozen_string_literal: true

DatabaseCleaner.strategy = :transaction

class Minitest::Spec
  before :each do
    DatabaseCleaner.start
  end

  after :each do
    DatabaseCleaner.clean
  end
end

# with the minitest-around gem, this may be used instead:
class Minitest::Spec
  around do |tests|
    DatabaseCleaner.cleaning(&tests)
  end
end
