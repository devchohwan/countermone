class StudentReferral < ApplicationRecord
  belongs_to :referred_student, class_name: "Student"
  belongs_to :referrer,         class_name: "Student"

  validates :referred_student_id, uniqueness: { scope: :referrer_id }
end
