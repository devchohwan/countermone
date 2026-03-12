class AddStatOffsetsToEnrollments < ActiveRecord::Migration[8.0]
  def change
    add_column :enrollments, :consecutive_weeks_offset, :integer, default: 0, null: false
    add_column :enrollments, :gift_voucher_eligible_offset, :integer, default: 0, null: false
    add_column :enrollments, :pass_offset, :integer, default: 0, null: false
  end
end
