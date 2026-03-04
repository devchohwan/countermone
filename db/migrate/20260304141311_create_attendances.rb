class CreateAttendances < ActiveRecord::Migration[8.0]
  def change
    create_table :attendances do |t|
      t.references :student,  null: false, foreign_key: true
      t.references :schedule, null: false, foreign_key: true
      t.references :payment,  null: false, foreign_key: true
      t.datetime :checked_in_at
      t.datetime :checked_out_at
      t.string   :error_type
      t.timestamps
    end
  end
end
