class StudentsController < ApplicationController
  before_action :set_student, only: %i[show edit update destroy leave return dropout complete_contact update_memo]

  def index
    @teachers = Teacher.by_position
    @students = Student.includes(:enrollments, :teachers)
    @students = @students.where(status: params[:status]) if params[:status].present?
    @students = @students.where("name LIKE ? OR attendance_code LIKE ?", "%#{params[:q]}%", "%#{params[:q]}%") if params[:q].present?

    if params[:teacher_id].present? || params[:lesson_day].present?
      scope = Enrollment.where(status: "active")
      scope = scope.where(teacher_id: params[:teacher_id]) if params[:teacher_id].present?
      scope = scope.where(lesson_day: params[:lesson_day])  if params[:lesson_day].present?
      @students = @students.where(id: scope.select(:student_id))
    end

    @students = @students.order(:name)

    @total_count  = @students.count
    @page         = [params[:page].to_i, 1].max
    @total_pages  = [(@total_count / 50.0).ceil, 1].max
    @page         = [@page, @total_pages].min
    @students     = @students.offset((@page - 1) * 50).limit(50)
  end

  def show
    @enrollments = @student.enrollments.includes(:teacher, :payments, :schedules)
  end

  def new
    @student = Student.new
    @student.attendance_code = suggest_attendance_code(@student)
    @student.enrollments.build.payments.build
    @teachers = Teacher.includes(:teacher_subjects).all
  end

  def create
    @student = Student.new(student_params)
    @student.status ||= "active"
    @student.first_enrolled_at ||= Date.today
    @student.waiting_expires_at = Date.today + 14.days if @student.status == "pending"

    referrer_count = Array(params[:referrer_ids]).reject(&:blank?).size
    @student.referral_discount_pending = referrer_count if referrer_count > 0

    ActiveRecord::Base.transaction do
      @student.enrollments.each do |enrollment|
        enrollment.status = "active"
        enrollment.payments.each do |payment|
          payment.student = @student
          payment.subject = enrollment.subject
          payment.fully_paid = (payment.payment_type == "new")
        end
      end

      if @student.save
        save_referrers(@student)
        redirect_to @student, notice: "수강생이 등록되었습니다."
      else
        @teachers = Teacher.includes(:teacher_subjects).all
        render :new, status: :unprocessable_entity
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    @teachers = Teacher.includes(:teacher_subjects).all
    @student.errors.add(:base, e.message)
    render :new, status: :unprocessable_entity
  end

  def edit
    @teachers = Teacher.includes(:teacher_subjects).all
  end

  def update
    # teacher 변경 전 enrollment별 이전 teacher_id 기록
    old_teacher_ids = @student.enrollments.index_by(&:id).transform_values(&:teacher_id)

    if @student.update(student_params)
      # teacher_id가 바뀐 enrollment의 scheduled 수업도 일괄 업데이트
      @student.enrollments.each do |enrollment|
        old_tid = old_teacher_ids[enrollment.id]
        next if old_tid.nil? || enrollment.teacher_id == old_tid
        enrollment.schedules.where(status: "scheduled", teacher_id: old_tid)
                  .update_all(teacher_id: enrollment.teacher_id)
      end
      save_referrers(@student)
      redirect_to @student, notice: "수강생 정보가 수정되었습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def update_memo
    @student.update!(memo: params[:student][:memo])
    redirect_to student_path(@student), notice: "메모가 저장되었습니다."
  end

  def destroy
    @student.destroy
    redirect_to students_path, notice: "수강생이 삭제되었습니다."
  end

  def leave
    redirect_to @student, alert: "과목별 휴원은 각 클래스 카드에서 처리해주세요."
  end

  def return
    redirect_to @student
  end

  def dropout
    @student.enrollments.where(status: %w[active leave]).each(&:dropout!)
    redirect_to @student, notice: "퇴원 처리되었습니다."
  end

  def complete_contact
    @student.update!(contact_due: nil)
    redirect_back fallback_location: root_path, notice: "#{@student.name} 연락 완료 처리되었습니다."
  end

  def search
    q = params[:q].to_s.strip
    students = q.length >= 1 ? Student.includes(enrollments: :teacher).where("name LIKE ?", "%#{q}%").order(:name).limit(20) : []
    render json: students.map do |s|
      teachers = s.enrollments.select { |e| e.status == "active" }.map { |e| e.teacher.name }.uniq
      label = teachers.any? ? "#{s.name}(#{teachers.join(",")})" : s.name
      { id: s.id, name: s.name, label: label }
    end
  end

  def check_attendance_code
    code = params[:code]
    student_id = params[:student_id]
    
    duplicate = Student.where(attendance_code: code, status: "active")
    duplicate = duplicate.where.not(id: student_id) if student_id.present?
    
    if duplicate.exists?
      render json: { available: false, student_name: duplicate.first.name }
    else
      render json: { available: true }
    end
  end

  private

  def set_student
    @student = Student.find(params[:id])
  end

  def student_params
    params.require(:student).permit(
      :name, :phone, :age, :attendance_code, :status, :rank,
      :has_car, :consent_form, :second_transfer_form, :cover_recorded,
      :reason_for_joining, :own_problem, :desired_goal, :first_enrolled_at,
      :expected_return, :leave_reason, :real_leave_reason, :contact_due,
      :refund_leave, :review_discount_applied, :review_url,
      :review_due, :interview_discount_applied, :interview_completed,
      :memo, :waiting_expires_at,
      enrollments_attributes: [
        :id, :teacher_id, :subject, :lesson_day, :lesson_time, :status,
        payments_attributes: [
          :id, :payment_type, :subject, :months, :total_lessons, :amount,
          :payment_method, :starts_at, :deposit_amount, :deposit_paid_at,
          :balance_amount, :balance_paid_at, :fully_paid
        ]
      ]
    )
  end

  def save_referrers(student)
    ids = Array(params[:referrer_ids]).map(&:to_i).uniq.reject(&:zero?).first(7)
    student.student_referrals.destroy_all
    ids.each do |referrer_id|
      next if referrer_id == student.id
      student.student_referrals.create!(referrer_id: referrer_id)
    end
    # 피추천인 첫 완납 결제가 있으면 추천인들에게 할인 대기 알림
    # (notify_referrer_if_applicable은 save 시점에 referrers가 비어있어 여기서 처리)
    if ids.any? && student.payments.where(fully_paid: true).exists?
      Student.where(id: ids).where.not(id: student.id).each do |referrer|
        referrer.increment!(:referral_discount_pending)
      end
    end
  end

  def suggest_attendance_code(student)
    return "" if student.phone.blank?
    base = student.phone.last(4)
    return base unless Student.where(attendance_code: base, status: "active").exists?
    extended = base + base.last
    return extended unless Student.where(attendance_code: extended, status: "active").exists?
    base[1..3] + base[0]
  end
end
