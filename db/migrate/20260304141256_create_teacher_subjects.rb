class CreateTeacherSubjects < ActiveRecord::Migration[8.0]
  def change
    create_table :teacher_subjects do |t|
      t.references :teacher, null: false, foreign_key: true
      t.string :subject, null: false
      t.timestamps
    end
  end
end
