class PricePlan < ApplicationRecord
  SUBJECTS = %w[클린보컬 언클린보컬 기타 작곡 믹싱1차 믹싱2차].freeze

  validates :subject, presence: true, inclusion: { in: SUBJECTS }
  validates :months,  presence: true, numericality: { greater_than: 0 }
  validates :amount,  presence: true, numericality: { greater_than: 0 }

  scope :active, -> { where(active: true) }

  def self.find_amount(subject, months)
    active.find_by(subject: subject, months: months)&.amount
  end
end
