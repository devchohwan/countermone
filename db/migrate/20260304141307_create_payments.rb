class CreatePayments < ActiveRecord::Migration[8.0]
  def change
    create_table :payments do |t|
      t.references :student,    null: false, foreign_key: true
      t.references :enrollment, null: false, foreign_key: true
      t.string  :payment_type,   null: false
      t.string  :subject,        null: false
      t.integer :months
      t.integer :total_lessons,  null: false
      t.integer :amount,         null: false
      t.string  :payment_method, null: false
      t.boolean :before_lesson,  default: false
      t.integer :deposit_amount, default: 0
      t.datetime :deposit_paid_at
      t.integer :balance_amount, default: 0
      t.datetime :balance_paid_at
      t.boolean :fully_paid,     default: false
      t.boolean :refunded,       default: false
      t.integer :refund_amount,  default: 0
      t.text    :refund_reason
      t.date    :starts_at,      null: false
      t.timestamps
    end
  end
end
