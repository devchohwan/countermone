class AddTrialToSchedules < ActiveRecord::Migration[8.0]
  def change
    add_column :schedules, :trial, :boolean, default: false, null: false
    add_column :schedules, :gift_voucher_id, :bigint
    change_column_null :schedules, :payment_id, true
    add_index :schedules, :gift_voucher_id
  end
end
