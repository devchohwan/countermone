class CreateDiscounts < ActiveRecord::Migration[8.0]
  def change
    create_table :discounts do |t|
      t.references :payment, null: false, foreign_key: true
      t.string  :discount_type, null: false
      t.integer :amount,        null: false
      t.text    :memo
      t.timestamps
    end
  end
end
