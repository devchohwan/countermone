class CreateGiftVouchers < ActiveRecord::Migration[8.0]
  def change
    create_table :gift_vouchers do |t|
      t.references :student,    null: false, foreign_key: true
      t.references :enrollment, null: false, foreign_key: true
      t.date    :issued_at
      t.boolean :used,          default: false
      t.string  :used_class
      t.date    :expires_at
      t.timestamps
    end
  end
end
