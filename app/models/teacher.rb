class Teacher < ApplicationRecord
  has_many :teacher_subjects, dependent: :destroy
  has_many :enrollments
  has_many :students, through: :enrollments
  has_many :schedules
  has_many :breaktime_openings, dependent: :destroy

  SUBJECTS = %w[클린보컬 언클린보컬 기타 작곡 믹싱].freeze

  validates :name, presence: true

  default_scope { order(Arel.sql("COALESCE(position, 9999), name")) }

  def teaches?(subject)
    teacher_subjects.exists?(subject: subject)
  end
end
