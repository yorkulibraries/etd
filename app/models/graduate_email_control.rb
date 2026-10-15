# frozen_string_literal: true

class GraduateEmailControl < ApplicationRecord
  validates :generation, numericality: { only_integer: true, greater_than: 0 }
  validates :id, inclusion: { in: [1] }
end
