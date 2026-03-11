class SlotsController < ApplicationController
  def check
    teacher_id  = params[:teacher_id].to_i
    subject     = params[:subject].to_s
    lesson_day  = params[:lesson_day].to_s
    lesson_time = params[:lesson_time].to_s

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
    count = query.count

    render json: { count: count, max: 3, available: count < 3 }
  end
end
