class Enrollment < ApplicationRecord
  STATUSES  = %w[active leave dropout].freeze
  LESSON_DAYS = %w[monday tuesday wednesday thursday friday saturday sunday].freeze

  belongs_to :student
  belongs_to :teacher
  has_many :payments, dependent: :destroy
  has_many :schedules, through: :payments
  has_many :gift_vouchers, dependent: :destroy

  accepts_nested_attributes_for :payments

  validates :subject,     presence: true, inclusion: { in: TeacherSubject::SUBJECTS }
  validates :lesson_day,  presence: true, inclusion: { in: LESSON_DAYS }
  validates :lesson_time, presence: true
  validates :status,      inclusion: { in: STATUSES }

  validate :teacher_teaches_subject
  validate :lesson_time_within_business_hours

  def leave!
    update_columns(status: "leave", leave_at: Date.today)
    student.update_columns(status: "leave") if student.enrollments.where(status: "active").none?
  end

  def return!(return_date = Date.today)
    frozen = schedules.where(status: "scheduled").order(:lesson_date).to_a
    frozen.each_with_index do |schedule, i|
      schedule.update_columns(lesson_date: next_lesson_date(return_date, lesson_day, i))
    end
    update_columns(status: "active", leave_at: nil, return_at: return_date)
    student.update_columns(status: "active")
  end

  def dropout!
    schedules.where(status: "scheduled").where("lesson_date > ?", Date.today).destroy_all
    update_columns(status: "dropout")
    student.update_columns(status: "dropout") if student.enrollments.where(status: %w[active leave]).none?
  end

  def returnable?
    payments.exists?
  end

  def frozen_scheduled_count
    schedules.where(status: "scheduled").count
  end

  private

  def next_lesson_date(start_date, lesson_day_name, n)
    day_map = { "monday" => 1, "tuesday" => 2, "wednesday" => 3,
                "thursday" => 4, "friday" => 5, "saturday" => 6, "sunday" => 0 }
    target_wday = day_map[lesson_day_name]
    first = start_date.dup
    first += 1.day until first.wday == target_wday
    first + (n * 7).days
  end

  def teacher_teaches_subject
    return unless teacher.present? && subject.present?
    unless teacher.teacher_subjects.exists?(subject: subject)
      errors.add(:teacher, "해당 선생님은 이 과목을 담당하지 않습니다")
    end
  end

  def lesson_time_within_business_hours
    return unless lesson_day.present? && lesson_time.present?
    t = lesson_time
    start_hour = t.respond_to?(:hour) ? t.hour : t.to_s.split(":").first.to_i
    start_min  = t.respond_to?(:min)  ? t.min  : t.to_s.split(":").second.to_i
    minutes = start_hour * 60 + start_min

    valid = if lesson_day == "monday"
      minutes >= 14 * 60 && minutes <= 17 * 60
    else
      minutes >= 13 * 60 && minutes <= 21 * 60
    end
    errors.add(:lesson_time, "해당 요일의 운영 시간 외입니다") unless valid
  end
end
