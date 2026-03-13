class Teacher < ApplicationRecord
  has_many :teacher_subjects, dependent: :destroy
  has_many :enrollments
  has_many :students, through: :enrollments
  has_many :schedules
  has_many :breaktime_openings, dependent: :destroy

  SUBJECTS = %w[클린보컬 언클린보컬 기타 작곡 믹싱1차 믹싱2차].freeze

  validates :name, presence: true

  scope :by_position, -> { order(Arel.sql("COALESCE(position, 9999), name")) }
  scope :non_military, -> { where(military: false) }

  def teaches?(subject)
    teacher_subjects.exists?(subject: subject)
  end
end
