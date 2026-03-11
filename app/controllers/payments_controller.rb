class PaymentsController < ApplicationController
  before_action :set_payment, only: %i[show refund pay_balance destroy]

  def index
    scope = Payment.includes(:student, :enrollment, :discounts)
                   .order(created_at: :desc)

    if params[:q].present?
      scope = scope.joins(:student).where("students.name LIKE ?", "%#{params[:q]}%")
    end

    if params[:date].present?
      date = Date.parse(params[:date]) rescue nil
      scope = scope.where(created_at: date.beginning_of_day..date.end_of_day) if date
    end

    @pagy, @payments = pagy(scope, limit: 50)
  end

  def show
    @student  = @payment.student
    @payments = Payment.includes(:discounts).where(student: @student).order(:created_at)

    enrollments = @student.enrollments.order(:id)
    @schedule_groups = enrollments.map do |enrollment|
      page     = (params["page_#{enrollment.id}"] || 1).to_i
      per_page = 8
      all      = enrollment.schedules.order(:lesson_date)
      total    = all.count
      records  = all.offset((page - 1) * per_page).limit(per_page)
      {
        enrollment: enrollment,
        schedules:  records,
        page:       page,
        total:      total,
        per_page:   per_page,
        total_pages: (total.to_f / per_page).ceil
      }
    end.reject { |g| g[:total].zero? }
  end

  def new
    @enrollment  = Enrollment.find(params[:enrollment_id]) if params[:enrollment_id]
    @payment     = Payment.new(enrollment: @enrollment)
    @price_plans = PricePlan.active.order(:subject, :months)

    if @enrollment
      @is_renewal = @enrollment.payments.exists?
      if @is_renewal
        @multi_class_discount = 0
        @multi_class_memo     = nil
        last_lesson = @enrollment.schedules.order(:lesson_date).last
        @default_starts_at = last_lesson ? last_lesson.lesson_date + 7.days : Date.today
      else
        has_qualifying = @enrollment.student.enrollments
          .where(status: "active")
          .where.not(id: @enrollment.id)
          .any? { |e| e.schedules.where(status: "scheduled").count > 0 }
        @multi_class_discount = has_qualifying ? 50_000 : 0
        @multi_class_memo     = has_qualifying ? "다중 수강 할인" : nil
      end
    end
  end

  def create
    @payment = Payment.new(payment_params)

    # 다개월 할인 자동 적용
    apply_multi_month_discount(@payment) if @payment.months.to_i > 1
    # 중복 수강 할인
    apply_multi_class_discount(@payment)
    # 신규 등록 시 waiting_expires_at 초기화
    @payment.enrollment.student.update!(waiting_expires_at: nil) if @payment.fully_paid?

    if @payment.save
      redirect_to student_path(@payment.student, tab: @payment.enrollment_id), notice: "결제가 등록되었습니다."
    else
      @enrollment  = @payment.enrollment
      @price_plans = PricePlan.active.order(:subject, :months)
      render :new, status: :unprocessable_entity
    end
  end

  def refund
    if @payment.update(refunded: true, refund_amount: params[:refund_amount] || @payment.refund_amount_calculated,
                       refund_reason: params[:refund_reason])
      @payment.schedules.where(status: "scheduled").destroy_all
      redirect_to @payment, notice: "환불 처리되었습니다."
    else
      redirect_to @payment, alert: "환불 처리 실패"
    end
  end

  def destroy
    student = @payment.student
    @payment.schedules.destroy_all
    @payment.discounts.destroy_all
    @payment.destroy!
    redirect_to student_path(student), notice: "결제가 삭제되었습니다."
  end

  def pay_balance
    if @payment.update(fully_paid: true, balance_paid_at: Time.current,
                       balance_amount: params[:balance_amount] || @payment.balance_amount)
      @payment.enrollment.student.update!(waiting_expires_at: nil)
      redirect_to @payment, notice: "잔금 납부 처리되었습니다."
    else
      redirect_to @payment, alert: "처리 실패"
    end
  end

  private

  def set_payment
    @payment = Payment.find(params[:id])
  end

  def payment_params
    params.require(:payment).permit(
      :student_id, :enrollment_id, :payment_type, :subject, :months,
      :total_lessons, :amount, :payment_method, :before_lesson,
      :deposit_amount, :deposit_paid_at, :balance_amount, :balance_paid_at,
      :fully_paid, :starts_at
    )
  end

  def apply_multi_month_discount(payment)
    plan_price     = PricePlan.find_amount(payment.subject, 1)
    multi_price    = PricePlan.find_amount(payment.subject, payment.months)
    return unless plan_price && multi_price
    discount_amount = (plan_price * payment.months.to_i) - multi_price
    return unless discount_amount > 0
    payment.discounts.build(
      discount_type: "multi_month",
      amount: discount_amount,
      memo: "#{payment.months}개월 다개월 할인"
    )
  end

  def apply_multi_class_discount(payment)
    enrollment = payment.enrollment
    # 연장결제: 이미 결제 내역 있으면 할인 없음
    return if enrollment.payments.exists?
    # 신규클래스: 다른 active enrollment 중 잔여≥1 있으면 5만원
    has_qualifying = enrollment.student.enrollments
      .where(status: "active")
      .where.not(id: enrollment.id)
      .any? { |e| e.schedules.where(status: "scheduled").count > 0 }
    return unless has_qualifying
    payment.discounts.build(
      discount_type: "multi_class",
      amount: 50_000,
      memo: "다중 수강 할인"
    )
  end
end
