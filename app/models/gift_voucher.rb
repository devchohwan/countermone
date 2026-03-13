class GiftVoucher < ApplicationRecord
  belongs_to :student
  belongs_to :enrollment
  has_one    :trial_schedule, -> { where(trial: true) }, class_name: "Schedule", foreign_key: :gift_voucher_id, dependent: :destroy

  validates :issued_at,  presence: true
  validates :expires_at, presence: true

  scope :active, -> { where(used: false).where("expires_at >= ?", Date.today) }
  scope :expiring_soon, -> { where(used: false).where(expires_at: ..1.month.from_now.to_date) }
end
