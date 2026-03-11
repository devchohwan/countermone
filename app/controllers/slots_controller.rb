class SlotsController < ApplicationController
  def check
    teacher_id = params[:teacher_id].to_i
    subject    = params[:subject].to_s
    from       = Date.parse(params[:from]) rescue Date.today
    weeks      = (params[:weeks] || 4).to_i.clamp(1, 8)

    range_dates = (from...(from + weeks * 7)).to_a
    teacher_ids = teacher_id > 0 ? [teacher_id] : []

    regular_counts = Schedule.where(
      teacher_id: teacher_ids, subject: subject, lesson_date: range_dates
    ).where(status: %w[scheduled attended late deducted pass emergency_pass holiday])
     .group(:teacher_id, :lesson_date).count

    makeup_counts = Schedule.where(
      makeup_teacher_id: teacher_ids, subject: subject, makeup_date: range_dates
    ).where(status: %w[makeup_scheduled makeup_done])
     .group(:makeup_teacher_id, :makeup_date).count

    slot_counts = Hash.new(0)
    regular_counts.each { |(tid, date), cnt| slot_counts[[tid, date]] += cnt }
    makeup_counts.each  { |(tid, date), cnt| slot_counts[[tid, date]] += cnt }

    grid = {}
    range_dates.each do |date|
      grid[date.to_s] = slot_counts[[teacher_id, date]] || 0
    end

    render json: {
      from:  from.to_s,
      dates: range_dates.map(&:to_s),
      grid:  grid
    }
  end
end
