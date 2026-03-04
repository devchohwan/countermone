class GiftVoucherExpiryJob < ApplicationJob
  queue_as :default

  def perform
    expiry_threshold = Date.today + 1.month
    GiftVoucher.where(used: false)
               .where(expires_at: ..expiry_threshold)
               .includes(:student)
               .each do |voucher|
      student = voucher.student
      student.update!(contact_due: Date.today) unless student.contact_due
    end
  end
end
