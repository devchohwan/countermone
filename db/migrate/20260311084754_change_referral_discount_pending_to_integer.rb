class ChangeReferralDiscountPendingToInteger < ActiveRecord::Migration[8.0]
  def up
    # boolean true → 1, false → 0
    add_column :students, :referral_discount_pending_int, :integer, default: 0, null: false
    Student.reset_column_information
    Student.where(referral_discount_pending: true).update_all(referral_discount_pending_int: 1)
    remove_column :students, :referral_discount_pending
    rename_column :students, :referral_discount_pending_int, :referral_discount_pending
  end

  def down
    add_column :students, :referral_discount_pending_bool, :boolean, default: false, null: false
    Student.reset_column_information
    Student.where("referral_discount_pending > 0").update_all(referral_discount_pending_bool: true)
    remove_column :students, :referral_discount_pending
    rename_column :students, :referral_discount_pending_bool, :referral_discount_pending
  end
end
