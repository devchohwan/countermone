module ApplicationHelper
  LESSON_DAY_KO = {
    "monday" => "월", "tuesday" => "화", "wednesday" => "수",
    "thursday" => "목", "friday" => "금", "saturday" => "토", "sunday" => "일"
  }.freeze

  STATUS_KO = {
    "active"       => "재원",
    "leave"        => "휴원",
    "dropout"      => "퇴원",
    "pending"      => "등록대기",
    "unregistered" => "미등록"
  }.freeze

  SCHEDULE_STATUS_KO = {
    "scheduled"       => "예정",
    "attended"        => "출석",
    "late"            => "지각",
    "absent"          => "결강",
    "deducted"        => "결석차감",
    "pass"            => "패스",
    "emergency_pass"  => "긴급패스",
    "makeup_scheduled" => "보강예정",
    "makeup_done"     => "보강완료",
    "minus_lesson"    => "마이너스"
  }.freeze

  def nav_link_class(path)
    active = request.path == path || (request.path.start_with?(path) && path != "/")
    active ? "active" : ""
  end

  def status_badge(status)
    daisy = {
      "active"       => "badge-success",
      "leave"        => "badge-warning",
      "dropout"      => "badge-ghost",
      "pending"      => "badge-info",
      "unregistered" => "badge-ghost"
    }
    cls = daisy[status] || "badge-ghost"
    content_tag(:span, ApplicationHelper::STATUS_KO[status] || status, class: "badge badge-sm #{cls}")
  end

  def schedule_status_badge(status)
    daisy = {
      "scheduled"        => "badge-info",
      "attended"         => "badge-success",
      "late"             => "badge-warning",
      "absent"           => "badge-warning badge-outline",
      "deducted"         => "badge-error",
      "pass"             => "badge-secondary",
      "emergency_pass"   => "badge-secondary badge-outline",
      "makeup_scheduled" => "badge-primary",
      "makeup_done"      => "badge-success badge-outline",
      "minus_lesson"     => "badge-error badge-outline"
    }
    cls = daisy[status] || "badge-ghost"
    content_tag(:span, ApplicationHelper::SCHEDULE_STATUS_KO[status] || status, class: "badge badge-xs #{cls}")
  end

  def status_badge_text(status)
    ApplicationHelper::STATUS_KO[status] || status
  end

  def schedule_status_ko(status)
    ApplicationHelper::SCHEDULE_STATUS_KO[status] || status
  end

  def lesson_day_ko(day)
    ApplicationHelper::LESSON_DAY_KO[day] || day
  end

  def format_amount(amount)
    "#{number_with_delimiter(amount)}원"
  end

  # 시간표 셀 표기 (plan.md 명세)
  # 기본: 홍길동
  # 첫수업: 홍길동(5.20첫)
  # 복귀: 홍길동(5.20복)
  # 차량: 홍길동(★)
  # 패스: 홍길동(5.20패)
  # 자리대기: 홍길동(대기)
  # 특이사항: 홍길동(5.20첫)>수강동의서받기
  def timetable_label(schedule)
    s = schedule.student
    e = schedule.enrollment
    tags = []

    if s.status == "pending"
      tags << "대기"
    elsif s.status == "leave"
      tags << "휴"
    elsif schedule.status.in?(%w[pass emergency_pass])
      tags << "패"
    elsif schedule.sequence == 1
      is_first_payment = e.payments.order(:created_at).first&.id == schedule.payment_id
      tags << (is_first_payment ? "첫" : "복")
    end

    tags << "★" if s.has_car?

    notes = []
    notes << "동의서" if !s.consent_form?
    notes << "2차전직서" if s.rank == "first" && s.second_transfer_form? == false && e.payments.count >= 4

    label = s.name
    label += "(#{tags.join('/')})" if tags.any?
    label += ">#{notes.join('/')}" if notes.any?
    label
  end

  # 보강 셀 표기: 홍길동(5.20보) or 홍길동(5.20보/범) — 원래 선생님과 다를 때 초성 표시
  def timetable_makeup_label(schedule, current_teacher)
    s = schedule.student
    if schedule.makeup_teacher_id == schedule.teacher_id
      "#{s.name}(보)"
    else
      initial = schedule.teacher&.name&.first || "?"
      "#{s.name}(보/#{initial})"
    end
  end

  def name_initial(name)
    name.to_s.first || "?"
  end
end
