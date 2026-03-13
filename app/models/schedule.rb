class Schedule < ApplicationRecord
  STATUSES = %w[
    scheduled attended late deducted
    pass emergency_pass holiday makeup_scheduled makeup_done
    minus_lesson
  ].freeze

  belongs_to :student
  belongs_to :enrollment
  belongs_to :payment,      optional: true
  belongs_to :teacher
  belongs_to :makeup_teacher, class_name: "Teacher", optional: true
  belongs_to :gift_voucher, optional: true
  has_one    :attendance, dependent: :destroy

  validates :lesson_date, presence: true
  validates :lesson_time, presence: true
  validates :subject,     presence: true
  validates :status,      inclusion: { in: STATUSES }
  validates :sequence,    numericality: { greater_than: 0 }, unless: :trial?
  validates :payment_id,  presence: true, unless: :trial?

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
      next_payment_first ? next_payment_first.lesson_date - 1.day : lesson_date + 6.days
    end

    lower..upper
  end

  # 슬롯 인원 수 (정규 + 보강 합산, 같은 과목, 같은 시간대)
  # time: "HH:MM" 문자열 또는 nil(시간 무시)
  def self.slot_count(teacher_id, subject, date, time = nil)
    hour = time ? time.to_s.split(":").first.to_i : nil

    regular_scope = where(teacher_id: teacher_id, subject: subject, lesson_date: date)
                      .where(status: %w[scheduled attended late])
    regular_scope = regular_scope.select { |s| s.lesson_time&.hour == hour } if hour
    regular_count = hour ? regular_scope.size : regular_scope.count

    makeup_scope = where(makeup_teacher_id: teacher_id, subject: subject, makeup_date: date)
                     .where(status: %w[makeup_scheduled makeup_done])
    makeup_scope = makeup_scope.select { |s| s.makeup_time&.hour == hour } if hour
    makeup_count = hour ? makeup_scope.size : makeup_scope.count

    regular_count + makeup_count
  end

  # 다과목 선생님 전용: 해당 시간대에 다른 과목이 있는지 확인
  def self.subject_conflict?(teacher_id, subject, date, time)
    hour = time.to_s.split(":").first.to_i

    regular_conflict = where(teacher_id: teacher_id, lesson_date: date)
                         .where(status: %w[scheduled attended late])
                         .where.not(subject: subject)
                         .any? { |s| s.lesson_time&.hour == hour }
    return true if regular_conflict

    makeup_conflict = where(makeup_teacher_id: teacher_id, makeup_date: date)
                        .where(status: %w[makeup_scheduled makeup_done])
                        .where.not(subject: subject)
                        .any? { |s| s.makeup_time&.hour == hour }
    makeup_conflict
  end

  after_commit :broadcast_timetable_refresh

  private

  def broadcast_timetable_refresh
    teacher_ids = [teacher_id, makeup_teacher_id].compact.uniq
    teacher_ids.each do |tid|
      Turbo::StreamsChannel.broadcast_refresh_to("teacher_timetable_#{tid}")
    end
  end
end
