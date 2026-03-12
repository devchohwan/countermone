class SlotsController < ApplicationController
  def check
    teacher_id  = params[:teacher_id].to_i
    subject     = params[:subject].to_s
    lesson_day  = params[:lesson_day].to_s
    lesson_time = params[:lesson_time].to_s
    parsed_lt   = lesson_time.present? ? (Time.zone.parse(lesson_time) rescue nil) : nil

    # ── 1. 정규 수강인원 (enrollment 기반) ──────────────────────
    eq = Enrollment.where(teacher_id: teacher_id, subject: subject,
                          lesson_day: lesson_day, status: 'active')
    eq = eq.where(lesson_time: parsed_lt) if parsed_lt
    enrollment_count = eq.count

    # ── 2. 날짜별 슬롯 (정규 + 보강 합산, lesson_time 필터 적용) ─
    range_dates = ((Date.today - 180)...(Date.today + 56))
                    .select { |d| d.strftime('%A').downcase == lesson_day }

    reg_query = Schedule.where(teacher_id: teacher_id, subject: subject,
                               lesson_date: range_dates)
                        .where(status: %w[scheduled attended late])
    reg_query = reg_query.where(lesson_time: parsed_lt) if parsed_lt
    regular_counts = reg_query.group(:lesson_date).count

    makeup_counts = Schedule.where(makeup_teacher_id: teacher_id, subject: subject,
                                   makeup_date: range_dates)
                            .where(status: %w[makeup_scheduled makeup_done])
                            .group(:makeup_date).count

    slot_counts = Hash.new(0)
    regular_counts.each { |date, cnt| slot_counts[date] += cnt }
    makeup_counts.each  { |date, cnt| slot_counts[date] += cnt }

    date_slots = range_dates.each_with_object({}) { |d, h| h[d.to_s] = slot_counts[d] || 0 }

    render json: {
      enrollment_count: enrollment_count,
      max:              3,
      date_slots:       date_slots
    }
  end
end
