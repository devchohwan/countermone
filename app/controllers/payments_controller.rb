class PaymentsController < ApplicationController
  before_action :set_payment, only: %i[show edit update destroy refund pay_balance]

  def index
    @payments = Payment.includes(:student, :enrollment, :discounts)
                       .order(created_at: :desc)
                       .limit(50)
  end

  def show
    @schedules = @payment.schedules.order(:lesson_date)
    @discounts = @payment.discounts
  end

  def new
    @enrollment = Enrollment.find(params[:enrollment_id]) if params[:enrollment_id]
    @payment    = Payment.new(enrollment: @enrollment)
    @price_plans = PricePlan.active.order(:subject, :months)
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
      redirect_to @payment, notice: "결제가 등록되었습니다."
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
    active_count = payment.enrollment.student.enrollments.where(status: "active").count
    return unless active_count >= 2
    discount_amount = (active_count - 1) * 50_000
    payment.discounts.build(
      discount_type: "multi_class",
      amount: discount_amount,
      memo: "#{active_count}클래스 중복 수강 할인"
    )
  end
end
