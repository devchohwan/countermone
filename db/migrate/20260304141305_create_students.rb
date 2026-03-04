class CreateStudents < ActiveRecord::Migration[8.0]
  def change
    create_table :students do |t|
      t.string  :name,                       null: false
      t.string  :phone,                      null: false
      t.integer :age
      t.string  :attendance_code,            null: false
      t.string  :status,                     null: false, default: "active"
      t.string  :rank,                       null: false, default: "first"
      t.boolean :has_car,                    default: false
      t.boolean :consent_form,               default: false
      t.boolean :second_transfer_form,       default: false
      t.boolean :cover_recorded,             default: false
      t.text    :reason_for_joining
      t.text    :own_problem
      t.text    :desired_goal
      t.date    :first_enrolled_at
      t.boolean :expected_return
      t.text    :leave_reason
      t.text    :real_leave_reason
      t.date    :contact_due
      t.boolean :refund_leave,               default: false
      t.references :referrer, foreign_key: { to_table: :students }, index: true
      t.boolean :referral_discount_pending,  default: false
      t.boolean :review_discount_applied,    default: false
      t.string  :review_url
      t.date    :review_due
      t.boolean :interview_discount_applied, default: false
      t.boolean :interview_completed,        default: false
      t.boolean :gift_voucher_issued,        default: false
      t.date    :waiting_expires_at
      t.text    :memo
      t.timestamps
    end
  end
end
