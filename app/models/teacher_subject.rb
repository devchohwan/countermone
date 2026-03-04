class TeacherSubject < ApplicationRecord
  belongs_to :teacher

  SUBJECTS = %w[클린보컬 언클린보컬 기타 작곡 믹싱].freeze

  validates :subject, presence: true, inclusion: { in: SUBJECTS }
end
