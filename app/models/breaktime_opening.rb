class BreaktimeOpening < ApplicationRecord
  belongs_to :teacher

  validates :date, presence: true
end
