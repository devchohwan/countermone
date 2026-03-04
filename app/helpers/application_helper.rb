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
    active = request.path == path || request.path.start_with?(path) && path != "/"
    base   = "block px-3 py-2 rounded text-sm "
    active ? base + "bg-gray-700 text-white" : base + "text-gray-300 hover:bg-gray-700 hover:text-white"
  end

  def status_badge(status)
    colors = {
      "active"       => "bg-green-100 text-green-800",
      "leave"        => "bg-yellow-100 text-yellow-800",
      "dropout"      => "bg-gray-100 text-gray-600",
      "pending"      => "bg-blue-100 text-blue-800",
      "unregistered" => "bg-gray-100 text-gray-400"
    }
    color = colors[status] || "bg-gray-100 text-gray-600"
    content_tag(:span, STATUS_KO[status] || status, class: "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium #{color}")
  end

  def schedule_status_badge(status)
    colors = {
      "scheduled"        => "bg-blue-100 text-blue-700",
      "attended"         => "bg-green-100 text-green-700",
      "late"             => "bg-yellow-100 text-yellow-700",
      "absent"           => "bg-orange-100 text-orange-700",
      "deducted"         => "bg-red-100 text-red-700",
      "pass"             => "bg-purple-100 text-purple-700",
      "emergency_pass"   => "bg-pink-100 text-pink-700",
      "makeup_scheduled" => "bg-indigo-100 text-indigo-700",
      "makeup_done"      => "bg-teal-100 text-teal-700",
      "minus_lesson"     => "bg-red-100 text-red-800"
    }
    color = colors[status] || "bg-gray-100 text-gray-600"
    content_tag(:span, SCHEDULE_STATUS_KO[status] || status, class: "inline-flex items-center px-1.5 py-0.5 rounded text-xs #{color}")
  end

  def lesson_day_ko(day)
    LESSON_DAY_KO[day] || day
  end

  def format_amount(amount)
    "#{number_with_delimiter(amount)}원"
  end

  def timetable_label(schedule)
    s = schedule.student
    label = s.name
    label += "(★)" if s.has_car?
    label
  end
end
