class Payment < ApplicationRecord
  PAYMENT_TYPES   = %w[new deposit].freeze
  PAYMENT_METHODS = %w[card transfer cash].freeze

  belongs_to :student
  belongs_to :enrollment
  has_many :schedules,   dependent: :destroy
  has_many :attendances, through: :schedules
  has_many :discounts,   dependent: :destroy

  validates :payment_type,   inclusion: { in: PAYMENT_TYPES }
  validates :payment_method, inclusion: { in: PAYMENT_METHODS }
  validates :total_lessons,  numericality: { greater_than: 0 }
  validates :amount,         numericality: { greater_than_or_equal_to: 0 }
  validates :starts_at,      presence: true

  after_create  :generate_schedules
  after_create  :apply_attendance_event_if_pending
  after_create  :apply_referral_discount_if_pending
  after_create  :reset_minus_lesson_count
  after_commit  :set_review_due_if_applicable, on: :create
  after_save    :trigger_return_if_fully_paid

  # 수강 종료일: 동적 계산 (보강/패스 반영)
  def ends_at
    last_lesson = schedules.maximum(:lesson_date)
    last_makeup = schedules.maximum(:makeup_date)
    [ last_lesson, last_makeup ].compact.max
  end

  def refund_amount_calculated
    return deposit_amount if !fully_paid?

    base_lessons = if discounts.where(discount_type: "attendance_event").exists?
      total_lessons - 1
    else
      total_lessons
    end

    attended = schedules.where(status: %w[attended makeup_done deducted late]).count
    remaining = [ base_lessons - attended, 0 ].max
    return 0 if base_lessons.zero?

    (amount.to_f * remaining / base_lessons).round
  end

  private

  def generate_schedules
    total_lessons.times.each_with_index do |_, i|
      lesson_date = calculate_nth_lesson_date(starts_at, enrollment.lesson_day, i)
      schedules.create!(
        student:     student,
        enrollment:  enrollment,
        teacher:     enrollment.teacher,
        lesson_date: lesson_date,
        lesson_time: enrollment.lesson_time,
        subject:     enrollment.subject,
        status:      "scheduled",
        sequence:    i + 1
      )
    end
  end

  def calculate_nth_lesson_date(start_date, lesson_day, n)
    day_map = {
      "monday" => 1, "tuesday" => 2, "wednesday" => 3,
      "thursday" => 4, "friday" => 5, "saturday" => 6, "sunday" => 0
    }
    target_wday = day_map[lesson_day]
    first_lesson = start_date.dup
    first_lesson += 1.day until first_lesson.wday == target_wday
    first_lesson + (n * 7).days
  end

  def apply_attendance_event_if_pending
    return unless enrollment.attendance_event_pending?
    discounts.create!(discount_type: "attendance_event", amount: 0, memo: "12주 개근 1회 무료")
    enrollment.update!(attendance_event_pending: false)
  end

  def apply_referral_discount_if_pending
    return unless student.referral_discount_pending?
    discounts.create!(discount_type: "referral", amount: 50_000, memo: "지인 할인 자동 적용")
    student.update!(referral_discount_pending: false)
  end

  def trigger_return_if_fully_paid
    return unless saved_change_to_fully_paid? && fully_paid?
    enrollment.return! if enrollment.status == "leave"
  end

  def reset_minus_lesson_count
    enrollment.update_column(:minus_lesson_count, 0) if enrollment.minus_lesson_count > 0
  end

  def set_review_due_if_applicable
    return unless discounts.where(discount_type: "review").exists?
    base_date = (balance_paid_at || deposit_paid_at)&.to_date
    student.update!(review_due: base_date + 7.days) if base_date
  end
end
