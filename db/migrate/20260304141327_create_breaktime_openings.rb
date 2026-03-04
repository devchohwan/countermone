class CreateBreaktimeOpenings < ActiveRecord::Migration[8.0]
  def change
    create_table :breaktime_openings do |t|
      t.references :teacher, null: false, foreign_key: true
      t.date   :date,        null: false
      t.string :created_by
      t.timestamps
    end
  end
end
