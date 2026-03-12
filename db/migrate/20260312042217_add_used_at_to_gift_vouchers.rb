class AddUsedAtToGiftVouchers < ActiveRecord::Migration[8.0]
  def change
    add_column :gift_vouchers, :used_at, :date
  end
end
