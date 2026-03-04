class CreatePricePlans < ActiveRecord::Migration[8.0]
  def change
    create_table :price_plans do |t|
      t.string :subject, null: false
      t.integer :months, null: false
      t.integer :amount, null: false
      t.boolean :active, default: true
      t.timestamps
    end
  end
end
