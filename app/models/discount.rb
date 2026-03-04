class Discount < ApplicationRecord
  TYPES = %w[multi_month referral multi_class review interview attendance_event].freeze

  belongs_to :payment

  validates :discount_type, presence: true, inclusion: { in: TYPES }
  validates :amount,        numericality: { greater_than_or_equal_to: 0 }
end
