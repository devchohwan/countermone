class Student < ApplicationRecord
  STATUSES = %w[active leave dropout pending unregistered].freeze
  RANKS    = %w[first second].freeze

  belongs_to :referrer, class_name: "Student", optional: true
  has_many :referrals, class_name: "Student", foreign_key: "referrer_id", dependent: :nullify, inverse_of: :referrer
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
