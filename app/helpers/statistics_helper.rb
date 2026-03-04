module StatisticsHelper
  def generate_closing_message(assigns)
    date        = assigns["date"] || Date.today
    payments    = assigns["daily_payments"] || []
    first_p     = assigns["first_payments"] || []
    extra_p     = assigns["extra_payments"] || []
    leaves      = assigns["daily_leaves"] || []
    dropouts    = assigns["daily_dropouts"] || []
    returns     = assigns["daily_returns"] || []

    lines = []
    lines << "📊 #{date.strftime('%m/%d')} 마감"
    lines << ""
    lines << "💳 결제"
    lines << "총 #{payments.count}건 / #{number_with_delimiter(payments.sum(&:amount))}원"
    lines << "첫결제 #{first_p.count}건 / 추가 #{extra_p.count}건"
    lines << ""
    lines << "📋 출석 현황"
    lines << "휴원 #{leaves.count}명 / 퇴원 #{dropouts.count}명 / 복귀 #{returns.count}명"
    lines << ""
    lines << "✏️ 특이사항"
    lines << "(직접 입력)"
    lines.join("\n")
  end
end
