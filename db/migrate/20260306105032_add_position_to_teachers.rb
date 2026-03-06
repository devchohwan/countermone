class AddPositionToTeachers < ActiveRecord::Migration[8.0]
  def change
    add_column :teachers, :position, :integer
    Teacher.order(:name).each_with_index do |teacher, i|
      teacher.update_column(:position, i + 1)
    end
  end
end
