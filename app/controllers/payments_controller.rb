class PaymentsController < ApplicationController
  before_action :set_payment, only: %i[show edit update refund pay_balance complete_deposit destroy]

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

  def edit
    @enrollment = @payment.enrollment
  end

  def update
    old_total     = @payment.total_lessons
    old_starts_at = @payment.starts_at

    ActiveRecord::Base.transaction do
      @payment.assign_attributes(payment_update_params)

      new_total     = @payment.total_lessons
      new_starts_at = @payment.starts_at

      # starts_at 변경 → scheduled 수업 날짜 재계산 (sequence 기반)
      if old_starts_at != new_starts_at
        reschedule_by_sequence(@payment, new_starts_at)
      end

      # total_lessons 변경
      if new_total != old_total
        adjust_lesson_count(@payment, old_total, new_total)
      end

      # deposit 타입: balance_paid_at 설정 시 fully_paid = true
      if @payment.payment_type == "deposit" && @payment.balance_paid_at.present?
        @payment.fully_paid = true
      end

      @payment.save!
    end

    respond_to do |format|
      format.html { redirect_to payment_path(@payment), notice: "결제 정보가 수정되었습니다." }
      format.json { render json: { ok: true } }
    end
  rescue ActiveRecord::RecordInvalid, RuntimeError => e
    respond_to do |format|
      format.html do
        @enrollment = @payment.enrollment
        flash.now[:alert] = e.message
        render :edit, status: :unprocessable_entity
      end
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
    end
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

  def done
    @enrollment_id = params[:enrollment_id]
    render layout: false
  end

  def create
    @payment = Payment.new(payment_params)

    # 다개월 할인 자동 적용
    apply_multi_month_discount(@payment) if @payment.months.to_i > 1
    # 중복 수강 할인
    apply_multi_class_discount(@payment)
    # 후기 할인
    apply_review_discounts(@payment)
    # 신규 등록 시 waiting_expires_at 초기화
    @payment.enrollment.student.update!(waiting_expires_at: nil) if @payment.fully_paid?

    if @payment.save
      if params[:cafe_review] == "1" || params[:video_review] == "1"
        @payment.enrollment.update_column(:last_review_discount_at, Date.today)
      end
      if params[:popup] == "1"
        return redirect_to payment_done_path(enrollment_id: @payment.enrollment_id)
      end
      redirect_to student_path(@payment.student, tab: @payment.enrollment_id), notice: "결제가 등록되었습니다."
    else
      @enrollment  = @payment.enrollment
      @price_plans = PricePlan.active.order(:subject, :months)
      render :new, status: :unprocessable_entity
    end
  end

  def refund
    if @payment.update(refunded: true, fully_paid: false, refund_amount: params[:refund_amount] || @payment.refund_amount_calculated,
                       refund_reason: params[:refund_reason])
      @payment.schedules.where(status: "scheduled").destroy_all
      cleanup_gift_vouchers(@payment)
      redirect_to @payment, notice: "환불 처리되었습니다."
    else
      redirect_to @payment, alert: "환불 처리 실패"
    end
  end

  def destroy
    student = @payment.student
    cleanup_gift_vouchers(@payment)
    @payment.schedules.destroy_all
    @payment.discounts.destroy_all
    @payment.destroy!
    redirect_to student_path(student), notice: "결제가 삭제되었습니다."
  end

  def pay_balance
    update_attrs = {
      fully_paid:      true,
      balance_paid_at: Time.current,
      balance_amount:  params[:balance_amount].presence || @payment.balance_amount,
      payment_method:  params[:payment_method].presence || @payment.payment_method
    }
    if @payment.update(update_attrs)
      @payment.enrollment.student.update!(waiting_expires_at: nil)
      redirect_to @payment, notice: "잔금 납부 처리되었습니다."
    else
      redirect_to @payment, alert: "처리 실패"
    end
  end

  def complete_deposit
    update_attrs = {
      fully_paid:      true,
      balance_paid_at: Time.current,
      balance_amount:  params[:balance_amount].presence || @payment.balance_amount,
      payment_method:  params[:payment_method].presence || @payment.payment_method
    }
    if @payment.update(update_attrs)
      @payment.enrollment.student.update!(waiting_expires_at: nil)
      redirect_back fallback_location: root_path, notice: "#{@payment.student.name} 완납 처리되었습니다."
    else
      redirect_back fallback_location: root_path, alert: "처리 실패"
    end
  end

  private

  def cleanup_gift_vouchers(payment)
    enrollment = payment.enrollment
    student    = payment.student
    enrollment.gift_vouchers.where(used: false).destroy_all
    student.update!(gift_voucher_issued: false) unless student.gift_vouchers.where(used: false).exists?
  end

  def set_payment
    @payment = Payment.find(params[:id])
  end

  def payment_update_params
    params.require(:payment).permit(
      :months, :total_lessons, :amount, :payment_method, :starts_at,
      :deposit_amount, :deposit_paid_at, :balance_amount, :balance_paid_at, :fully_paid
    )
  end

  # starts_at 변경 시 scheduled 수업 날짜를 sequence 기반으로 재계산
  def reschedule_by_sequence(payment, new_starts_at)
    enrollment = payment.enrollment
    payment.schedules.where(status: "scheduled").order(:sequence).each do |s|
      new_date = calculate_nth_lesson_date(new_starts_at, enrollment.lesson_day, s.sequence - 1)
      s.update_column(:lesson_date, new_date)
    end
  end

  # total_lessons 변경 시 수업 추가/삭제
  def adjust_lesson_count(payment, old_total, new_total)
    diff = new_total - old_total
    enrollment = payment.enrollment

    if diff > 0
      last_s    = payment.schedules.order(:lesson_date).last
      last_date = last_s&.lesson_date || payment.starts_at
      last_seq  = payment.schedules.maximum(:sequence).to_i
      diff.times do |i|
        payment.schedules.create!(
          student:     payment.student,
          enrollment:  enrollment,
          teacher:     enrollment.teacher,
          lesson_date: last_date + ((i + 1) * 7).days,
          lesson_time: enrollment.lesson_time,
          subject:     enrollment.subject,
          status:      "scheduled",
          sequence:    last_seq + i + 1
        )
      end
    else
      to_remove = payment.schedules.where(status: "scheduled").order(lesson_date: :desc).limit(-diff)
      if to_remove.count < -diff
        attended = payment.schedules.where.not(status: "scheduled").count
        raise "출석 처리된 수업이 #{attended}회 있어 #{attended}회 미만으로 줄일 수 없습니다."
      end
      to_remove.destroy_all
    end
  end

  def payment_params
    params.require(:payment).permit(
      :student_id, :enrollment_id, :payment_type, :subject, :months,
      :total_lessons, :amount, :payment_method, :before_lesson,
      :deposit_amount, :deposit_paid_at, :balance_amount, :balance_paid_at,
      :fully_paid, :starts_at
    )
  end

  def apply_review_discounts(payment)
    if params[:cafe_review] == "1"
      payment.discounts.build(discount_type: "review", amount: 50_000, memo: "3개월 카페후기 할인")
    end
    if params[:video_review] == "1"
      payment.discounts.build(discount_type: "review", amount: 50_000, memo: "6개월 영상후기 할인")
    end
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
