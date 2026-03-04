# 선생님 데이터
teacher_data = [
  { name: "미라쿠도", subjects: %w[믹싱] },
  { name: "오또",    subjects: %w[클린보컬 기타 작곡 믹싱] },
  { name: "도현",    subjects: %w[언클린보컬] },
  { name: "무성",    subjects: %w[클린보컬] },
  { name: "범",      subjects: %w[클린보컬] }
]

teacher_data.each do |data|
  teacher = Teacher.find_or_create_by!(name: data[:name])
  data[:subjects].each do |subject|
    teacher.teacher_subjects.find_or_create_by!(subject: subject)
  end
end

puts "선생님 #{Teacher.count}명 생성"

# 가격표 데이터
price_plan_data = [
  { subject: "클린보컬",  months: 1, amount: 370_000 },
  { subject: "클린보컬",  months: 3, amount: 950_000 },
  { subject: "언클린보컬", months: 1, amount: 370_000 },
  { subject: "언클린보컬", months: 3, amount: 950_000 },
  { subject: "믹싱",     months: 1, amount: 280_000 },
  { subject: "믹싱",     months: 4, amount: 990_000 },
  { subject: "작곡",     months: 1, amount: 350_000 },
  { subject: "작곡",     months: 3, amount: 950_000 },
  { subject: "기타",     months: 1, amount: 300_000 },
  { subject: "기타",     months: 3, amount: 770_000 }
]

price_plan_data.each do |data|
  PricePlan.find_or_create_by!(subject: data[:subject], months: data[:months]) do |pp|
    pp.amount = data[:amount]
  end
end

puts "가격표 #{PricePlan.count}건 생성"

# 관리자 계정
User.find_or_create_by!(email_address: "admin@monemusic.com") do |u|
  u.password = "password123"
end

puts "관리자 계정 생성 완료"
