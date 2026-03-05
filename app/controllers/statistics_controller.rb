class StatisticsController < ApplicationController
  def index
    @date = params[:date] ? Date.parse(params[:date]) : Date.today
    daily_stats(@date)
  end

  def daily
    @date = params[:date] ? Date.parse(params[:date]) : Date.today
    daily_stats(@date)
    render :index
  end

  def monthly
    @month = params[:month] ? Date.parse("#{params[:month]}-01") : Date.today.beginning_of_month
    @payments_monthly = Payment.where(fully_paid: true)
                               .where(updated_at: @month.beginning_of_month..@month.end_of_month)
    @monthly_revenue  = @payments_monthly.sum(:amount)
  end

  private

  # 휴원 시점의 수강 기간 분류 (plan.md: 시작전 / 3개월이하 / 3개월초과)
  def leave_duration_months(enrollment)
    attended = enrollment.schedules.where(status: %w[attended makeup_done deducted]).count
    months_attended = attended / 4.0
    if months_attended < 0.5
      :before   # 시작 전 (수업 거의 안 들음)
    elsif months_attended <= 3
      :short    # 3개월 이하
    else
      :long     # 3개월 초과
    end
  end

  def daily_stats(date)
    @daily_payments = Payment.where(fully_paid: true)
                             .where("DATE(updated_at) = ?", date)
                             .includes(:student, :enrollment, :discounts)

    @first_payments  = @daily_payments.select { |p| p.enrollment.payments.order(:created_at).first == p }
    @extra_payments  = @daily_payments - @first_payments

    @daily_leaves         = Enrollment.where(leave_at: date).includes(:student, :payments)
    @daily_leaves_before  = @daily_leaves.select { |e| leave_duration_months(e) == :before }
    @daily_leaves_short   = @daily_leaves.select { |e| leave_duration_months(e) == :short }
    @daily_leaves_long    = @daily_leaves.select { |e| leave_duration_months(e) == :long }
    @daily_dropouts = Enrollment.where(status: "dropout").where("DATE(updated_at) = ?", date).includes(:student)
    @daily_returns  = Enrollment.where(status: "active").where(return_at: date).includes(:student)

    @contact_completed = Student.where(contact_due: date).includes(:enrollments)

    otto = Teacher.find_by(name: "오또")
    if otto
      @otto_students_clean    = otto.enrollments.where(status: "active", subject: "클린보컬").count
      @otto_students_nonclean = otto.enrollments.where(status: "active").where.not(subject: "클린보컬").count
    end
  end
end
