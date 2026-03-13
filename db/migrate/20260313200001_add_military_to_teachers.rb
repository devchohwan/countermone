class AddMilitaryToTeachers < ActiveRecord::Migration[8.0]
  def change
    add_column :teachers, :military, :boolean, default: false, null: false

    reversible do |dir|
      dir.up do
        teacher = Teacher.create!(name: "군인", military: true, position: 9998)
        TeacherSubject::SUBJECTS.each do |subject|
          TeacherSubject.create!(teacher: teacher, subject: subject)
        end
      end
      dir.down do
        Teacher.find_by(name: "군인", military: true)&.destroy
      end
    end
  end
end
