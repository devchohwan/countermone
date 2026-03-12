class GiftVouchersController < ApplicationController
  before_action :set_voucher, only: [:use]

  def create
    enrollment = Enrollment.find(params[:enrollment_id])
    student    = enrollment.student

    if GiftVoucher.where(enrollment: enrollment).exists?
      return redirect_back fallback_location: root_path, alert: "이미 발급된 상품권이 있습니다."
    end

    weeks = student.gift_voucher_eligible_weeks_for(enrollment)
    if weeks < 24
      return redirect_back fallback_location: root_path, alert: "24주 조건 미충족 (현재 #{weeks}주)."
    end

    GiftVoucher.create!(
      student:    student,
      enrollment: enrollment,
      issued_at:  Date.today,
      expires_at: Date.today + 6.months
    )
    student.update!(gift_voucher_issued: true)
    redirect_back fallback_location: root_path, notice: "#{student.name} 지류상품권 발급 완료."
  end

  def use
    if @voucher.used?
      return redirect_back fallback_location: root_path, alert: "이미 사용된 상품권입니다."
    end
    if @voucher.expires_at < Date.today
      return redirect_back fallback_location: root_path, alert: "만료된 상품권입니다."
    end

    used_class = params[:used_class].to_s.strip
    if used_class.blank?
      return redirect_back fallback_location: root_path, alert: "사용 과목을 선택해주세요."
    end
    if used_class == @voucher.enrollment.subject
      return redirect_back fallback_location: root_path, alert: "발급 과목(#{used_class})에는 사용할 수 없습니다."
    end

    @voucher.update!(used: true, used_at: Date.today, used_class: used_class)
    redirect_back fallback_location: root_path, notice: "상품권 사용 처리 완료 (#{used_class})."
  end

  private

  def set_voucher
    @voucher = GiftVoucher.find(params[:id])
  end
end
