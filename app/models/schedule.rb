class Schedule < ApplicationRecord
  STATUSES = %w[
    scheduled attended late deducted
    pass emergency_pass holiday makeup_scheduled makeup_done
    minus_lesson
  ].freeze

  belongs_to :student
  belongs_to :enrollment
  belongs_to :payment
  belongs_to :teacher
  belongs_to :makeup_teacher, class_name: "Teacher", optional: true
  has_one    :attendance, dependent: :destroy

  validates :lesson_date, presence: true
  validates :lesson_time, presence: true
  validates :subject,     presence: true
  validates :status,      inclusion: { in: STATUSES }
  validates :sequence,    numericality: { greater_than: 0 }

  scope :today,       -> { where(lesson_date: Date.today) }
  scope :scheduled,   -> { where(status: "scheduled") }
  scope :need_makeup, -> { where(status: "makeup_scheduled") }

  # 보강 가능 기간 계산
  def makeup_available_range
    prev_schedule = payment.schedules
                           .where("lesson_date < ?", lesson_date)
                           .order(:lesson_date).last
    next_schedule = payment.schedules
                           .where("lesson_date > ?", lesson_date)
                           .order(:lesson_date).first

    lower = prev_schedule ? prev_schedule.lesson_date + 1.day : payment.starts_at

    upper = if next_schedule
      next_schedule.lesson_date - 1.day
    else
      next_payment_first = enrollment.payments
                                     .where("starts_at > ?", payment.starts_at)
                                     .order(:starts_at).first
                                     &.schedules&.order(:lesson_date)&.first
      next_payment_first ? next_payment_first.lesson_date - 1.day : lesson_date + 28.days
    end

    lower..upper
  end

  # 슬롯 인원 수 (정규 + 보강 합산, 같은 과목)
  def self.slot_count(teacher_id, subject, date)
    regular = where(teacher_id: teacher_id, subject: subject, lesson_date: date)
                .where(status: %w[scheduled attended])
                .count
    makeup  = where(makeup_teacher_id: teacher_id, subject: subject, makeup_date: date)
                .where(status: %w[makeup_scheduled makeup_done])
                .count
    regular + makeup
  end
end
