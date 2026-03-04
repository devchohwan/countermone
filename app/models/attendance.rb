class Attendance < ApplicationRecord
  ERROR_TYPES = %w[double_checkin missing_class old_payment expired_date].freeze

  belongs_to :student
  belongs_to :schedule
  belongs_to :payment

  validates :error_type, inclusion: { in: ERROR_TYPES }, allow_nil: true
end
