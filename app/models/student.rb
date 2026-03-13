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
    enrollment.schedules.where(status: %w[scheduled makeup_scheduled]).count
  end

  def consecutive_weeks_for_raw(enrollment)
    return 0 if enrollment.status == "leave"

    candidates = [Date.new(2025, 10, 28), enrollment.last_attendance_event_at]
    candidates << enrollment.return_at if enrollment.leave_at && enrollment.return_at
    since = candidates.compact.max
    enrollment.schedules
              .where("lesson_date >= ?", since)
              .where("lesson_date <= ? OR status IN (?)", Date.today, %w[attended late makeup_done pass])
              .order(lesson_date: :desc)
              .to_a
              .take_while { |s| %w[attended makeup_done].include?(s.status) }
              .count
  end

  def consecutive_weeks_for(enrollment)
    return 0 if enrollment.status == "leave"

    computed = consecutive_weeks_for_raw(enrollment)
    [computed + (enrollment.consecutive_weeks_offset || 0), 0].max
  end

  def total_attended_weeks_for(enrollment)
    enrollment.schedules.where(status: %w[attended makeup_done deducted]).count
  end

  # 후기 마일스톤 카운터: 마지막 후기할인 적용일(또는 복귀일) 기준, 패스 끊김
  def review_weeks_for_raw(enrollment)
    return 0 if enrollment.status == "leave"

    candidates = [Date.new(2025, 10, 28), enrollment.last_review_discount_at, enrollment.return_at]
    since = candidates.compact.max
    enrollment.schedules
              .where("lesson_date >= ?", since)
              .where("lesson_date <= ? OR status IN (?)", Date.today, %w[attended late makeup_done pass])
              .order(lesson_date: :desc)
              .to_a
              .take_while { |s| %w[attended makeup_done].include?(s.status) }
              .count
  end

  def review_weeks_for(enrollment)
    return 0 if enrollment.status == "leave"

    computed = review_weeks_for_raw(enrollment)
    [computed + (enrollment.gift_voucher_eligible_offset || 0), 0].max
  end

  # 지류상품권 조건: 휴원 후 복귀일 기준 (없으면 첫 결제 시작일)로 카운트
  # 패스 포함, 지각 포함, 보강 포함, 차감 포함
  def gift_voucher_eligible_weeks_for_raw(enrollment)
    return 0 if enrollment.status == "leave"

    since_date = enrollment.return_at ||
                 enrollment.payments.order(:created_at).first&.starts_at ||
                 enrollment.created_at.to_date
    enrollment.schedules
              .where("lesson_date >= ?", since_date)
              .where(status: %w[attended late makeup_done deducted])
              .count
  end

  def gift_voucher_eligible_weeks_for(enrollment)
    return 0 if enrollment.status == "leave"

    computed = gift_voucher_eligible_weeks_for_raw(enrollment)
    [computed + (enrollment.gift_voucher_eligible_offset || 0), 0].max
  end

  def available_passes_for(enrollment)
    total_months = enrollment.payments.where(fully_paid: true).sum(:months)
    used_passes  = enrollment.schedules.where(status: "pass").count
    [total_months - used_passes + (enrollment.pass_offset || 0), 0].max
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
