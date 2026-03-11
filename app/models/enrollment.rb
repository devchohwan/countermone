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
    future = schedules.where(status: "scheduled").where("lesson_date > ?", Date.today)
    update_columns(remaining_on_leave: future.count)
    future.destroy_all
    update_columns(status: "leave", leave_at: Date.today)
    student.update_columns(status: "leave") if student.enrollments.where(status: "active").none?
  end

  def return!
    count = remaining_on_leave
    if count > 0
      payment = payments.order(:created_at).last
      if payment
        start_date = Date.today
        max_seq    = payment.schedules.maximum(:sequence) || 0
        count.times.each_with_index do |_, i|
          lesson_date = next_lesson_date(start_date, lesson_day, i)
          payment.schedules.create!(
            student:     student,
            enrollment:  self,
            teacher:     teacher,
            lesson_date: lesson_date,
            lesson_time: lesson_time,
            subject:     subject,
            status:      "scheduled",
            sequence:    max_seq + i + 1
          )
        end
      end
    end
    update_columns(status: "active", leave_at: nil, return_at: nil, remaining_on_leave: 0)
    student.update_columns(status: "active")
  end

  def dropout!
    schedules.where(status: "scheduled").where("lesson_date > ?", Date.today).destroy_all
    update_columns(status: "dropout")
    student.update_columns(status: "dropout") if student.enrollments.where(status: %w[active leave]).none?
  end

  def returnable?
    payments.where(fully_paid: true).exists?
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
