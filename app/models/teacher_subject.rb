class TeacherSubject < ApplicationRecord
  belongs_to :teacher

  SUBJECTS = %w[클린보컬 언클린보컬 기타 작곡 믹싱1차 믹싱2차].freeze

  validates :subject, presence: true, inclusion: { in: SUBJECTS }
end
