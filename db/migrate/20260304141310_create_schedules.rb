class CreateSchedules < ActiveRecord::Migration[8.0]
  def change
    create_table :schedules do |t|
      t.references :student,    null: false, foreign_key: true
      t.references :enrollment, null: false, foreign_key: true
      t.references :payment,    null: false, foreign_key: true
      t.references :teacher,    null: false, foreign_key: true
      t.date    :lesson_date,   null: false
      t.time    :lesson_time,   null: false
      t.string  :subject,       null: false
      t.string  :status,        null: false, default: "scheduled"
      t.integer :sequence,      null: false
      t.date    :makeup_date
      t.time    :makeup_time
      t.bigint  :makeup_teacher_id
      t.boolean :makeup_approved, default: false
      t.text    :pass_reason
      t.timestamps
    end

    add_foreign_key :schedules, :teachers, column: :makeup_teacher_id
    add_index :schedules, :makeup_teacher_id
    add_index :schedules, :lesson_date
    add_index :schedules, :makeup_date
  end
end
