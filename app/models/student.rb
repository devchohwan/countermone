class Student < ApplicationRecord
  STATUSES = %w[active leave dropout pending unregistered].freeze
  RANKS    = %w[first second].freeze

  # 추천인 관계 (복수, 최대 7명)
  has_many :student_referrals,    foreign_key: :referred_student_id, dependent: :destroy
  has_many :referrers,            through: :student_referrals, source: :referrer
  has_many :referred_referrals,   class_name: "StudentReferral", foreign_key: :referrer_id, dependent: :destroy
  has_many :referred_students,    through: :referred_referrals, source: :referred_student
  has_many :enrollments, dependent: :destroy
  has_many :teachers, through: :enrollments
  has_many :payments, through: :enrollments
  has_many :schedules, through: :payments
  has_many :attendances, through: :schedules
  has_many :gift_vouchers, dependent: :destroy

  accepts_nested_attributes_for :enrollments

  validates :name,            presence: true
  validates :phone,           presence: true
  validates :attendance_code, presence: true
  validates :status,          inclusion: { in: STATUSES }
  validates :rank,            inclusion: { in: RANKS }

  before_save :update_rank_from_transfer_form
  validate    :attendance_code_unique_among_active

  def remaining_lessons_for(enrollment)
    enrollment.schedules.where(status: "scheduled").count
  end

  def consecutive_weeks_for(enrollment)
    enrollment.schedules
              .where("lesson_date >= ?", Date.new(2025, 10, 28))
              .order(lesson_date: :desc)
              .to_a
              .take_while { |s| %w[attended makeup_done].include?(s.status) }
              .count
  end

  def total_attended_weeks_for(enrollment)
    enrollment.schedules.where(status: %w[attended makeup_done deducted]).count
  end

  def available_passes_for(enrollment)
    total_months = enrollment.payments.where(fully_paid: true).sum(:months)
    used_passes  = enrollment.schedules.where(status: "pass").count
    total_months - used_passes
  end

  private

  def update_rank_from_transfer_form
    self.rank = "second" if second_transfer_form? && rank == "first"
  end

  def attendance_code_unique_among_active
    duplicate = Student.where(attendance_code: attendance_code, status: "active")
                       .where.not(id: id)
    errors.add(:attendance_code, "재원 수강생 중 중복된 코드입니다") if duplicate.exists?
  end
end
