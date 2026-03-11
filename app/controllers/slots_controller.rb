class SlotsController < ApplicationController
  def check
    teacher_id  = params[:teacher_id].to_i
    subject     = params[:subject].to_s
    lesson_day  = params[:lesson_day].to_s
    lesson_time = params[:lesson_time].to_s

    # ── 1. 정규 수강인원 (enrollment 기반) ──────────────────────
    query = Enrollment.where(
      teacher_id: teacher_id,
      subject:    subject,
      lesson_day: lesson_day,
      status:     'active'
    )
    if lesson_time.present?
      parsed = Time.zone.parse(lesson_time) rescue nil
      query  = query.where(lesson_time: parsed) if parsed
    end
    enrollment_count = query.count

    # ── 2. 날짜별 슬롯 (정규 + 보강 합산) ──────────────────────
    # 앞으로 8주 중 lesson_day에 해당하는 날짜만
    range_dates = (Date.today...(Date.today + 8 * 7))
                    .select { |d| d.strftime('%A').downcase == lesson_day }

    regular_counts = Schedule.where(
      teacher_id: teacher_id, subject: subject, lesson_date: range_dates
    ).where(status: %w[scheduled attended late deducted pass emergency_pass holiday])
     .group(:lesson_date).count

    makeup_counts = Schedule.where(
      makeup_teacher_id: teacher_id, subject: subject, makeup_date: range_dates
    ).where(status: %w[makeup_scheduled makeup_done])
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
