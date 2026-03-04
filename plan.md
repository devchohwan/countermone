# 모네뮤직 카운터 관리시스템 — 개발 플랜

---

## 기술 스택

- **백엔드**: Ruby on Rails 8
- **프론트엔드**: ERB + Hotwire (Turbo + Stimulus)
- **DB**: PostgreSQL
- **인증**: Rails 8 기본 Authentication Generator
- **CSS**: Tailwind CSS + shadcn/ui
- **백그라운드 잡**: Solid Queue (Rails 8 기본 포함)
- **다크모드**: shadcn 기본 지원, 사용자 토글 가능 (눈 보호)
- **반응형**: 불필요 (데스크탑/태블릿 전용)

---

## 핵심 설계 원칙

- Payment가 Schedule을 낳는다
- 이후 모든 조작과 계산은 Schedule 중심으로 돌아간다
- 잔여 횟수, 개근 카운트, 보강 가능 기간 등 모든 숫자는 Schedule 상태값을 집계하여 계산한다
- 데이터는 중앙 DB에서 파생된다. 결제 1건 등록 시 스케줄 생성 → 시간표 갱신 → 대시보드 갱신이 자동으로 이루어진다
- 수강생 1명은 N개의 클래스를 수강할 수 있다. 클래스 단위는 Enrollment로 관리한다

---

## 데이터 모델 및 스키마

---

### teachers
```
id               bigint PK
name             string    NOT NULL
created_at       datetime
updated_at       datetime
```

---

### teacher_subjects (선생님-과목 매핑)
```
id               bigint PK
teacher_id       bigint    FK → teachers.id   NOT NULL
subject          string    NOT NULL  -- 클린/언클린/기타/작곡/믹싱
created_at       datetime
updated_at       datetime
```

**Associations**
```ruby
# teacher.rb
has_many :teacher_subjects
has_many :subjects, through: :teacher_subjects  # subject 목록 조회용

# 선생님-과목 매핑 (고정 규칙)
# 믹싱:       미라쿠도, 오또
# 기타/작곡:  오또
# 언클린:     도현
# 클린:       오또 및 나머지 클린 선생님들
```

---

### price_plans (수업 금액 관리)
```
id               bigint PK
subject          string    NOT NULL  -- 클린/언클린/기타/작곡/믹싱
months           integer   NOT NULL  -- 개월 수
amount           integer   NOT NULL  -- 금액 (원)
active           boolean   DEFAULT true
created_at       datetime
updated_at       datetime
```

**기본 금액 (관리자 화면에서 수정 가능)**
| 과목 | 1개월 | 3개월 | 4개월 |
|---|---|---|---|
| 클린 | 370,000 | 950,000 | - |
| 언클린 | 370,000 | 950,000 | - |
| 믹싱 | 280,000 | - | 990,000 |
| 작곡 | 350,000 | 950,000 | - |
| 기타 | 300,000 | 770,000 | - |

**비고**
- 결제 등록 화면에서 subject + months 선택 시 amount 자동 조회
- 금액 변경 시 기존 결제건은 영향 없음 (payments.amount는 결제 시점 금액 고정)
- 관리자만 수정 가능

---

### students
```
id                          bigint PK
name                        string    NOT NULL
phone                       string    NOT NULL
age                         integer
attendance_code             string    NOT NULL
                                      -- 재원 수강생 간 유일
                                      -- DB UNIQUE 제약 없음, Rails validation으로만 처리
                                      -- (휴원 수강생과는 중복 허용해야 하므로)
status                      string    NOT NULL DEFAULT 'active'
                                      -- active/leave/dropout/pending/unregistered
rank                        string    NOT NULL DEFAULT 'first'
                                      -- first(1차전직) / second(2차전직)
has_car                     boolean   DEFAULT false
consent_form                boolean   DEFAULT false
second_transfer_form        boolean   DEFAULT false  -- true 시 rank → second 자동 변경
cover_recorded              boolean   DEFAULT false
reason_for_joining          text      -- 찾아온 이유
own_problem                 text      -- 본인의 문제점
desired_goal                text      -- 하고 싶은 것
first_enrolled_at           date
expected_return             boolean
leave_reason                text      -- 수강생이 언급한 사유
real_leave_reason           text      -- 예측 본심 사유
contact_due                 date
refund_leave                boolean   DEFAULT false
referrer_id                 bigint    FK → students.id
referral_discount_pending   boolean   DEFAULT false
                                      -- 피추천인 결제 완료 시 true
                                      -- 본인 다음 결제 시 할인 자동 적용 후 false로 리셋
review_discount_applied     boolean   DEFAULT false
review_url                  string
review_due                  date      -- paid_at + 7일, 7일 내 미입력 시 연락할 자동 등록
interview_discount_applied  boolean   DEFAULT false
interview_completed         boolean   DEFAULT false
gift_voucher_issued         boolean   DEFAULT false  -- 1개 이상 상품권 발급 여부 (요약용)
waiting_expires_at          date                         -- 2주 자리대기 만료일 (신규에게만 적용)
memo                        text
created_at                  datetime
updated_at                  datetime
```

**Associations**
```ruby
belongs_to :referrer, class_name: 'Student', optional: true
has_many :referrals, class_name: 'Student', foreign_key: 'referrer_id'
has_many :enrollments
has_many :teachers, through: :enrollments
has_many :payments, through: :enrollments
has_many :schedules, through: :payments
has_many :attendances, through: :schedules
```

**Callbacks**
```ruby
# 2차 전직서 수령 시 rank 자동 변경
before_save :update_rank_from_transfer_form

# 출결 코드 중복 체드 (재원 수강생 간, 휴원 수강생 제외)
validate :attendance_code_unique_among_active

# enrollment 상태 변경 시 student 상태 자동 동기화
# → enrollment.rb의 after_save callback에서 호출

private

def update_rank_from_transfer_form
  self.rank = 'second' if second_transfer_form? && rank == 'first'
end

def attendance_code_unique_among_active
  duplicate = Student.where(attendance_code: attendance_code, status: 'active')
                     .where.not(id: id)
  errors.add(:attendance_code, '재원 수강생 중 중복된 코드입니다') if duplicate.exists?
end
```

**계산 메서드**
```ruby
# 잔여 횟수 (enrollment별로 각각 계산)
def remaining_lessons_for(enrollment)
  enrollment.schedules.where(status: 'scheduled').count
end

# 개근 카운트 (enrollment별, 2025-10-28 이후 기준)
def consecutive_weeks_for(enrollment)
  enrollment.schedules
            .where('lesson_date >= ?', Date.new(2025, 10, 28))
            .order(lesson_date: :desc)
            .take_while { |s| %w[attended makeup_done].include?(s.status) }
            .count
end

# 결제 기준 재원 기간 (enrollment별, 출석 완료된 Schedule 수, 4주=1개월)
def total_attended_weeks_for(enrollment)
  enrollment.schedules.where(status: %w[attended makeup_done deducted]).count
end
```

---

### enrollments
```
id               bigint PK
student_id       bigint    FK → students.id   NOT NULL
teacher_id       bigint    FK → teachers.id   NOT NULL
subject          string    NOT NULL  -- 클린/언클린/기타/작곡/믹싱
lesson_day       string    NOT NULL  -- 수업 요일
lesson_time      time      NOT NULL  -- 수업 시간
status           string    NOT NULL DEFAULT 'active'
                           -- active(재원) / leave(휴원) / dropout(퇴원)
                           -- 과목별로 독립적으로 관리
leave_at              date      -- 휴원일
return_at             date      -- 복귀 예정일
remaining_on_leave    integer   DEFAULT 0
                                -- 휴원 시 삭제된 미래 Schedule 수 보존
                                -- 복귀 결제 시 이 숫자 기반으로 Schedule 재생성
minus_lesson_count        integer   DEFAULT 0
                                  -- 미결제 선수업 횟수 (enrollment별 관리)
                                  -- 다음 결제 시 total_lessons에서 차감하여 입력
attendance_event_pending  boolean   DEFAULT false
                                  -- 12주 개근 달성 시 true
                                  -- 다음 결제 시 1회 무료 discount 자동 생성 후 false
created_at            datetime
updated_at            datetime
```

**Associations**
```ruby
belongs_to :student
belongs_to :teacher
has_many :payments
has_many :schedules, through: :payments
```

**휴원/복귀 처리 로직**
```ruby
# 휴원 시: 미래 scheduled Schedule 삭제, 횟수 보존
def leave!
  future = schedules.where(status: 'scheduled').where('lesson_date > ?', Date.today)
  self.remaining_on_leave = future.count
  future.destroy_all
  update!(status: 'leave', leave_at: Date.today)
  # 모든 enrollment가 leave/dropout이면 student도 leave
  student.update!(status: 'leave') if student.enrollments.where(status: 'active').none?
end

# 복귀 결제 시: remaining_on_leave 기반으로 Schedule 재생성
# → Payment 생성 시 total_lessons = remaining_on_leave로 입력하면 자동 재생성
# → 완납(fully_paid: true)인 Payment가 생성된 시점에만 return! 호출
def return!
  update!(status: 'active', leave_at: nil, return_at: nil, remaining_on_leave: 0)
  student.update!(status: 'active')
end

# 복귀 가능 여부 체크 (완납자만)
def returnable?
  payments.where(fully_paid: true).exists?
end
```

**Validation**
```ruby
# 요일별 수업 가능 시간 검증
# 월요일: 14:00~17:00 (마지막 수업 시작 17:00)
# 화~일: 13:00~21:00 (마지막 수업 시작 21:00)
# 브레이크타임(18:00~19:00)은 기본 불가, breaktime_openings 있으면 허용
validate :lesson_time_within_business_hours

# 선생님이 해당 과목을 담당하는지 검증
validate :teacher_teaches_subject

def teacher_teaches_subject
  return unless teacher.present? && subject.present?
  unless teacher.teacher_subjects.exists?(subject: subject)
    errors.add(:teacher, '해당 선생님은 이 과목을 담당하지 않습니다')
  end
end

def lesson_time_within_business_hours
  return unless lesson_day.present? && lesson_time.present?
  t = lesson_time
  if lesson_day == 'monday'
    valid = t >= Tod::TimeOfDay.new(14, 0) && t <= Tod::TimeOfDay.new(17, 0)
  else
    valid = t >= Tod::TimeOfDay.new(13, 0) && t <= Tod::TimeOfDay.new(21, 0)
  end
  errors.add(:lesson_time, '해당 요일의 운영 시간 외입니다') unless valid
end
```

**비고**
- 수강생이 클래스를 추가할 때마다 enrollment를 새로 생성
- 중복 수강 할인은 student.enrollments.where(status: 'active').count 기준으로 자동 계산
- 클래스별 독립 상태 관리: 기타 휴원 + 클린 재원 동시 가능
- students.status는 수강생 전체 상태 (모든 enrollment가 leave/dropout일 때 자동 변경)
- enrollment dropout 시 히스토리 보존, 삭제 안 함
- enrollment별 minus_lesson_count로 어느 클래스 마이너스인지 명확히 구분

---

### payments
```
id               bigint PK
student_id       bigint    FK → students.id      NOT NULL
enrollment_id    bigint    FK → enrollments.id   NOT NULL
payment_type     string    NOT NULL
                           -- new(일반결제) / deposit(예약금으로 시작한 결제)
subject          string    NOT NULL
months           integer                      -- 개월 수
total_lessons    integer   NOT NULL           -- 총 수업 횟수 (1개월=4회)
amount           integer   NOT NULL           -- 총 결제 금액
payment_method   string    NOT NULL           -- card/transfer/cash
before_lesson    boolean   DEFAULT false
deposit_amount   integer   DEFAULT 0          -- 예약금 금액
deposit_paid_at  datetime                     -- 예약금 납부일
balance_amount   integer   DEFAULT 0          -- 잔금 금액
balance_paid_at  datetime                     -- 잔금 납부일
fully_paid       boolean   DEFAULT false      -- 완납 여부 (new는 생성 시 true, deposit은 잔금 납부 시 true)
refunded         boolean   DEFAULT false
refund_amount    integer   DEFAULT 0
refund_reason    text
starts_at        date      NOT NULL
created_at       datetime
updated_at       datetime
```

**ends_at — 컬럼 아님, 동적 계산 메서드**
```ruby
# 수강 종료일: 보강/패스로 마지막 수업이 밀려도 자동 반영
def ends_at
  last_lesson = schedules.maximum(:lesson_date)
  last_makeup = schedules.maximum(:makeup_date)
  [last_lesson, last_makeup].compact.max
end
```

**Associations**
```ruby
belongs_to :student
belongs_to :enrollment
has_many :schedules
has_many :attendances, through: :schedules
has_many :discounts
```

**Callbacks**
```ruby
after_create :generate_schedules
after_create :apply_attendance_event_if_pending
after_create :apply_referral_discount_if_pending
after_commit :set_review_due_if_applicable, on: :create
after_save :trigger_return_if_fully_paid

private

def generate_schedules
  enrollment = self.enrollment
  total_lessons.times.each_with_index do |_, i|
    lesson_date = calculate_nth_lesson_date(
      starts_at,
      enrollment.lesson_day,
      i
    )
    schedules.create!(
      student:     student,
      enrollment:  enrollment,
      teacher:     enrollment.teacher,
      lesson_date: lesson_date,
      lesson_time: enrollment.lesson_time,
      subject:     enrollment.subject,
      status:      'scheduled',
      sequence:    i + 1
    )
  end
end

# 수업 요일 기반 N번째 날짜 계산
def calculate_nth_lesson_date(starts_at, lesson_day, n)
  # lesson_day: "monday", "tuesday" 등
  day_map = { 'monday'=>1,'tuesday'=>2,'wednesday'=>3,
              'thursday'=>4,'friday'=>5,'saturday'=>6,'sunday'=>0 }
  target_wday = day_map[lesson_day]
  first_lesson = starts_at
  first_lesson += 1.day until first_lesson.wday == target_wday
  first_lesson + (n * 7).days
end

# 개근 이벤트 1회 무료 discount 자동 생성
def apply_attendance_event_if_pending
  return unless enrollment.attendance_event_pending?
  discounts.create!(discount_type: 'attendance_event', amount: 0, memo: '12주 개근 1회 무료')
  # total_lessons + 1 처리는 결제 등록 화면에서 상담원에게 안내
  enrollment.update!(attendance_event_pending: false)
end

# 추천인 다음 결제 시 지인 할인 자동 적용
def apply_referral_discount_if_pending
  return unless student.referral_discount_pending?
  discounts.create!(discount_type: 'referral', amount: 50_000, memo: '지인 할인 자동 적용')
  student.update!(referral_discount_pending: false)
end

# 완납 시 휴원 중인 enrollment 복귀 처리
def trigger_return_if_fully_paid
  return unless saved_change_to_fully_paid? && fully_paid?
  enrollment.return! if enrollment.status == 'leave'
end

# 후기 할인 적용 시 review_due 자동 설정 (완납일 + 7일)
def set_review_due_if_applicable
  if discounts.where(discount_type: 'review').exists?
    base_date = (balance_paid_at || deposit_paid_at)&.to_date
    student.update!(review_due: base_date + 7.days) if base_date
  end
end
```

---

### discounts
```
id               bigint PK
payment_id       bigint    FK → payments.id   NOT NULL
discount_type    string    NOT NULL
                           -- multi_month/referral/multi_class/review/interview/attendance_event
amount           integer   NOT NULL
memo             text
created_at       datetime
updated_at       datetime
```

**Associations**
```ruby
belongs_to :payment
```

---

### gift_vouchers
```
id               bigint PK
student_id       bigint    FK → students.id      NOT NULL
enrollment_id    bigint    FK → enrollments.id   NOT NULL  -- 어느 클래스 기준 발급인지
issued_at        date
used             boolean   DEFAULT false
used_class       string
expires_at       date
created_at       datetime
updated_at       datetime
```

**Associations**
```ruby
belongs_to :student
belongs_to :enrollment
```

**비고**
- enrollment별로 각각 24회차 도달 시 생성
- 만료 1개월 전 student.contact_due 자동 등록

---

### breaktime_openings
```
id               bigint PK
teacher_id       bigint    FK → teachers.id   NOT NULL
date             date      NOT NULL
created_by       string                        -- 개방 처리한 상담원 메모용
created_at       datetime
updated_at       datetime
```

**Associations**
```ruby
belongs_to :teacher
```

**비고**
- 브레이크타임(18:00~19:00) 슬롯은 기본 비활성
- 이 테이블에 레코드가 있는 날짜+선생님 조합만 보강 배정 가능
- 상담원이 수동으로 개방/취소

---

```
id                bigint PK
student_id        bigint    FK → students.id      NOT NULL
enrollment_id     bigint    FK → enrollments.id   NOT NULL
payment_id        bigint    FK → payments.id      NOT NULL
teacher_id        bigint    FK → teachers.id      NOT NULL
lesson_date       date      NOT NULL
lesson_time       time      NOT NULL
subject           string    NOT NULL  -- enrollment.subject에서 복사, slot_count 필터용
status            string    NOT NULL DEFAULT 'scheduled'
                            -- scheduled/attended/late/absent/deducted
                            -- pass/emergency_pass/makeup_scheduled/makeup_done
                            -- minus_lesson
sequence          integer   NOT NULL
makeup_date       date
makeup_time       time
makeup_teacher_id bigint    FK → teachers.id
makeup_approved   boolean   DEFAULT false
pass_reason       text
created_at        datetime
updated_at        datetime
```

**Associations**
```ruby
belongs_to :student
belongs_to :enrollment
belongs_to :payment
belongs_to :teacher
belongs_to :makeup_teacher, class_name: 'Teacher', optional: true
has_one :attendance
```

**스코프 및 핵심 메서드**
```ruby
scope :today,       -> { where(lesson_date: Date.today) }
scope :scheduled,   -> { where(status: 'scheduled') }
scope :need_makeup, -> { where(status: 'makeup_scheduled') }

# 보강 가능 기간 (앞뒤 정규 수업 사이)
# - 하한: 이전 수업 다음날. 이전 수업 없으면(첫 수업 결강) payment.starts_at
# - 상한: 다음 수업 전날. 다음 수업 없으면(마지막 수업 결강) 다음 결제분 첫 수업 전날.
#         다음 결제분도 없으면 상한 없음(nil)
def makeup_available_range
  prev_schedule = payment.schedules
                         .where('lesson_date < ?', lesson_date)
                         .order(:lesson_date).last
  next_schedule = payment.schedules
                         .where('lesson_date > ?', lesson_date)
                         .order(:lesson_date).first

  lower = prev_schedule ? prev_schedule.lesson_date + 1.day : payment.starts_at

  upper = if next_schedule
    next_schedule.lesson_date - 1.day
  else
    # 마지막 수업 결강: 다음 결제분 첫 수업 전날
    # 다음 결제분 없으면 보강 불가 (nil 반환)
    next_payment_first = enrollment.payments
                                   .where('starts_at > ?', payment.starts_at)
                                   .order(:starts_at).first
                                   &.schedules&.order(:lesson_date)&.first
    return nil unless next_payment_first
    next_payment_first.lesson_date - 1.day
  end

  lower..upper
end

# 슬롯 인원 체크 (정규 + 보강 합산, 최대 3명, 같은 과목)
# 보강은 정규 수업 시간과 다를 수 있으므로 time 기준 없이 날짜+선생님+과목으로만 체크
def self.slot_count(teacher_id, subject, date)
  regular = where(teacher_id: teacher_id, subject: subject, lesson_date: date)
              .where(status: %w[scheduled attended])
              .count
  makeup  = where(makeup_teacher_id: teacher_id, subject: subject, makeup_date: date)
              .where(status: %w[makeup_scheduled makeup_done])
              .count
  regular + makeup
end

# 다른 과목끼리는 한 슬롯에 편성 불가
# 보강 가능 선생님: enrollment.subject에 해당하는 teacher_subjects 기준으로 필터
```

---

### attendances
```
id               bigint PK
student_id       bigint    FK → students.id    NOT NULL
schedule_id      bigint    FK → schedules.id   NOT NULL
payment_id       bigint    FK → payments.id    NOT NULL
checked_in_at    datetime
checked_out_at   datetime
error_type       string
                 -- double_checkin/missing_class/old_payment/expired_date
created_at       datetime
updated_at       datetime
```

**Associations**
```ruby
belongs_to :student
belongs_to :schedule
belongs_to :payment
```

---

## Rails 파일 구성

### Models
```
app/models/
  teacher.rb
  teacher_subject.rb
  price_plan.rb
  breaktime_opening.rb
  student.rb
  enrollment.rb
  payment.rb
  discount.rb
  gift_voucher.rb
  schedule.rb
  attendance.rb
```

### Controllers
```
app/controllers/
  dashboard_controller.rb       -- 메인 대시보드
  students_controller.rb        -- 수강생 CRUD
  enrollments_controller.rb     -- 클래스 등록/수정
  payments_controller.rb        -- 결제 등록/환불
  schedules_controller.rb       -- 스케줄 조회/수정
  attendances_controller.rb     -- 출결 처리
  makeups_controller.rb         -- 보강 관리
  passes_controller.rb          -- 패스 관리
  timetable_controller.rb       -- 선생님별 시간표
  statistics_controller.rb      -- 통계/마감
  keypad_controller.rb          -- 출석 키패드 (별도 화면)
```

### Routes
```ruby
Rails.application.routes.draw do
  root 'dashboard#index'

  resources :students do
    member do
      patch :leave        # 휴원 처리
      patch :return       # 복귀 처리
      patch :dropout      # 퇴원 처리
    end
    resources :enrollments, shallow: true do
      member do
        patch :leave    # 클래스 휴원
        patch :return   # 클래스 복귀
        patch :dropout  # 클래스 퇴원
      end
    end
  end

  resources :payments do
    member do
      post :refund        # 환불 처리
      # 환불 시 review_url 미입력 여부 자동 체크
      # → 후기 할인 적용 결제인데 review_url 없으면 정규수업 금액 기준으로 환불 경고 표시
    end
  end

  resources :schedules do
    member do
      patch :attend
      patch :absent
      patch :pass
      patch :emergency_pass
      patch :makeup
    end
  end

  resources :attendances, only: %i[create update destroy]

  get  'timetable',             to: 'timetable#index'
  get  'timetable/:teacher_id', to: 'timetable#show'

  get  'keypad',                to: 'keypad#index'
  post 'keypad/checkin',        to: 'keypad#checkin'

  get  'statistics',            to: 'statistics#index'
  get  'statistics/daily',      to: 'statistics#daily'
  get  'statistics/monthly',    to: 'statistics#monthly'
end
```

---

## 개발 단계

---

### 1단계 — 수강생 + Enrollment + 결제 + 스케줄 자동 생성

**목표**: 핵심 원천 데이터 구축. 이 단계 없이 나머지 불가.

**작업 목록**
- [x] PostgreSQL 연결 및 DB 설정
- [x] Rails 8 기본 인증 설정
- [x] teachers 테이블 + Model + CRUD
- [x] price_plans 테이블 + Model + 관리자 CRUD
  - 기본 금액 seed 데이터 입력
  - 결제 등록 화면에서 subject + months 선택 시 amount 자동 조회
- [x] students 테이블 + Model
  - attendance_code 생성 로직 (뒷 4자리 → 중복 시 5자리 → 중간자리)
  - attendance_code_unique_among_active validation
  - 휴원자 복귀 시 코드 중복 체크 및 상담원 알림
  - second_transfer_form → rank 자동 변경 before_save callback
  - waiting_expires_at: 신규 등록 시 자동 설정 (등록일 + 14일), 결제 완료 시 nil로 초기화
  - remaining_lessons, consecutive_weeks, total_attended_weeks 계산 메서드
- [x] students CRUD 화면
  - 수강생 목록 (상태별 필터)
  - 수강생 상세 (enrollment 목록 + 수업 날짜 리스트 + 전체 히스토리)
  - 등록/수정 폼
  - 휴원/복귀/퇴원 처리 버튼
- [x] enrollments 테이블 + Model
  - 수강생당 N개 enrollment 가능
  - status별 클래스 상태 관리 (active/leave/dropout)
  - 중복 수강 할인 계산 기준 (active enrollment 수)
  - returnable? 메서드 (완납 여부 체크, 복귀 처리 전 검증)
  - 복귀 결제 화면에서 remaining_on_leave 자동 표시
- [x] payments 테이블 + Model
  - enrollment_id 참조
  - after_create :generate_schedules callback
  - calculate_nth_lesson_date 메서드 (starts_at + lesson_day 기반)
  - after_create :apply_referral_discount_if_pending
  - after_commit :set_review_due_if_applicable (완납 시점 기준)
  - 과목별 가격 자동 적용
  - 할인 자동 계산 (다개월/지인/중복수강/후기/인터뷰/개근이벤트)
  - 환불 금액 계산
    - fully_paid: false → deposit_amount 전액 환불 (수업 전 상태이므로)
    - fully_paid: true → amount 기준 잔여 비율 환불 (잔여 횟수 / 유효 총 횟수)
      - attendance_event discount 있는 결제: total_lessons에서 무료 횟수(1회) 제외
      - 예: total_lessons=5(4+1무료), 잔여 3회 → 4회 기준 3/4 환불
    - 후기 할인 적용 결제 + review_url 미입력 시 → 정규수업 금액 기준으로 환불
  - ends_at 동적 계산 메서드
  - 잔금 납부 시 fully_paid → true, balance_paid_at 업데이트 (별도 action)
  - 복귀 결제 화면에서 enrollment.remaining_on_leave 자동 표시
- [x] payments 등록/환불 화면
- [x] discounts 테이블 + Model
- [x] schedules 테이블 + Model
  - enrollment_id 참조
  - makeup_available_range 메서드
  - slot_count 메서드
  - 상태값 관리

**완료 기준**
- 결제 등록 시 해당 enrollment 기준으로 Schedule 자동 생성
- 수강생 상세에서 클래스별 수업 날짜 리스트 확인 가능
- 잔여 횟수가 Schedule 집계로 자동 계산
- 2개 이상 클래스 수강 시 각각 독립적으로 관리됨

---

### 2단계 — 출결 시스템 + 키패드

**목표**: 실제 출석 처리 및 오류 감지

**작업 목록**
- [x] attendances 테이블 + Model
- [x] 출석 키패드 화면 (태블릿 전용 레이아웃)
  - 숫자 키패드 UI
  - attendance_code 입력 → 수강생 특정 → 해당 시간대 Schedule 특정 → attended 처리
  - 수강생이 N개 클래스 수강 중이면 어느 클래스인지 선택 화면 표시
  - 출석 완료 시 수강생 이름 + 과목 + 회차 표시
  - 오류 케이스 자동 감지 및 상담원 알림
    - 2회 차감 오류 (같은 Schedule에 checked_in_at 중복)
  - 등원: checked_in_at 자동 기록
  - 하원: checkout 액션으로 checked_out_at 기록
- [x] 출결 관리 화면 (상담원용)
  - 시간대별 출석 현황 표시
  - 지각 / 결강 / 결석 처리
  - 결석 차감 처리
  - 보강완료 처리

**완료 기준**
- 키패드 코드 입력 시 Schedule 상태가 attended로 변경됨
- N개 클래스 수강생은 클래스 선택 화면이 표시됨
- 오류 발생 시 상담원 화면에 알림 표시

---

### 3단계 — 선생님별 시간표

**목표**: 스케줄 데이터를 시각적으로 표현

**작업 목록**
- [ ] timetable_controller
- [ ] 주간 시간표 화면
  - 선생님별 탭/필터
  - enrollment.status = 'active'인 Schedule만 렌더링 (휴원 수강생 제외)
  - 보강은 makeup_date 기준으로 별도 쿼리하여 해당 날짜 슬롯에 표시
  - 요일별 렌더링 시작 시간: 월요일 14:00, 화~일 13:00
  - 브레이크타임(18:00~19:00) 비활성 표시, breaktime_openings 있는 경우 활성화
  - 시간대별 슬롯 (slot_count 활용)
  - 슬롯당 최대 3명 자동 제한 (정규 + 보강 합산)
  - 3명 풀 슬롯 초록 표시
  - 브레이크타임 (18:00~19:00) 비활성 슬롯으로 표시 (기본값: 보강 불가)
  - 상담원이 수동으로 브레이크타임 슬롯 열기 가능 (모네님 확인 후)
  - 시간대별 주차 필요 대수 자동 표시 (has_car 기반)
  - 상태값별 표시
    - 기본: `홍길동`
    - 첫수업: `홍길동(5.20첫)`
    - 복귀: `홍길동(5.20복)`
    - 차량보유: `홍길동(★)`
    - 보강(담당 선생님): `홍길동(5.20보)`
    - 보강(타 선생님): `홍길동(5.20보/범)` — 원래 선생님 초성
    - 패스: `홍길동(5.20패)`
    - 자리대기(pending): `홍길동(대기)`
    - 특이사항: `홍길동(5.20첫)>수강동의서받기`
- [ ] 시간표 메모란 (자리 대기, 일정 변경 대기)

**완료 기준**
- 선생님별 주간 시간표 렌더링
- 슬롯 3명 풀이면 초록 표시 및 추가 배치 불가

---

### 4단계 — 보강/패스 관리

**목표**: 스케줄 변동 처리

**작업 목록**
- [ ] 보강 처리
  - makeup_available_range로 가능 기간 자동 계산
  - slot_count(teacher_id, subject, date)로 3명 미만 날짜만 표시 (시간 무관)
  - 보강 가능한 선생님은 teacher_subjects 기준으로 동일 과목 담당 선생님으로만 제한
  - 담당 선생님 슬롯 우선 표시, 불가 시 같은 과목 타 선생님 슬롯 표시
  - 보강 확정 시 Schedule.makeup_date, makeup_time, makeup_teacher_id, status → makeup_scheduled 업데이트
  - 믹싱 보강 승인 플로우 (makeup_approved 컬럼, 상담원이 선생님에게 확인 후 대신 처리)
    - 1차전직: 같은 주차인 다른 반 슬롯 자동 확인
    - 2차전직: 주차 무관, 상담원이 승인 후 배정
  - 당일 취소 보강 불가 처리
- [ ] 패스 처리
  - 결제분 기준 잔여 패스 횟수 자동 계산 (months 기준 발생, pass/emergency_pass 상태 집계)
  - 패스 적용 시 Schedule.status → pass
  - 패스 적용 시 consecutive_weeks 리셋 (schedules에서 재계산)
  - 당일 / 믹싱 패스 불가 처리
  - 2주 이상 선패스 요청 시 잔여 횟수 체크 및 경고
  - 긴급패스 → Schedule.status → emergency_pass (상담원 수동)
- [ ] 선생님별 패스 사용 시트 자동 기록

**완료 기준**
- 보강 시 가능한 슬롯만 자동 표시
- 패스 사용 시 개근 카운트 리셋
- 믹싱 보강 승인 플로우 작동

---

### 5단계 — 자동 계산 모듈

**목표**: 파생 데이터 자동화

**작업 목록**
- [ ] 결제자 자동 계산
  - 우선순위 순서로 표시 (중복 제거)
  1. fully_paid: false + 오늘 첫 Schedule 존재 → "예약금 — 오늘 첫수업, 완납 필요"
  2. fully_paid: false (첫수업 아닌 경우) → "잔금 미납"
  3. enrollment별 잔여 횟수 1 (fully_paid: true인 경우만) → "다음 결제 예정"
  - student 단위로 표시하되 클래스(과목) 명시
    - 예: "홍길동 — 클린 예약금, 오늘 첫수업 완납 필요"
    - 예: "홍길동 — 기타 잔금 미납"
    - 예: "홍길동 — 클린 다음 결제 예정 (수업 후)"
  - 수업 전/후 결제 구분 (before_lesson 기준)
- [ ] 연락할 리스트 자동 계산
  - student.contact_due 기준 당일 도래 (결제대기 / 상품권만료 / 후기기한 / 등록대기)
  - enrollment.return_at 기준 당일 도래 → 휴원 복귀 예정 연락 (enrollment별 체크)
  - student.waiting_expires_at 기준 당일 도래 → 2주 자리대기 만료 알림 (신규 수강생만)
  - 유형별 분류 및 클래스 명시 (홍길동 — 기타 복귀 예정)
  - 연락 완료 처리 → DB 자동 업데이트
- [ ] 개근 트래킹
  - 출석 처리 시마다 consecutive_weeks_for(enrollment) 재계산
  - 12주 달성 시 enrollment.attendance_event_pending → true, 상담원 알림
  - 다음 결제 시 apply_attendance_event_if_pending callback으로 discount 자동 생성
- [ ] 상품권 트래킹
  - enrollment별 total_attended_weeks_for(enrollment) 기준 24회차 도달 시 상담원 알림
  - 과목별로 각각 체크 (클린 24회, 기타 24회 각각 별도 상품권)
  - gift_voucher_expires_at 기준 1개월 전 contact_due 자동 등록
- [ ] 마이너스 수업 관리
  - 별도 Payment를 생성하지 않음
  - enrollment.minus_lesson_count에 기록 (클래스별 미결제 선수업 횟수)
  - 다음 결제 시 상담원이 total_lessons를 차감하여 입력 (예: 1회 마이너스 → 3회 입력)
  - 결제 완료 시 enrollment.minus_lesson_count 자동 초기화
- [ ] 지인 할인 양측 처리
  - 피추천인 결제 완료 시 추천인 student.referral_discount_pending → true
  - 추천인 다음 결제 시 apply_referral_discount_if_pending callback으로 자동 적용
- [ ] 후기 할인 review_due 자동 설정
  - 후기 할인 적용 결제 시 review_due = paid_at + 7일 자동 설정
  - 매일 review_due 도래 + review_url 미입력 수강생 → 연락할 자동 등록

**완료 기준**
- 오늘 결제/연락 대상이 자동 리스트업됨
- 12주 개근 달성 시 상담원 알림
- 지인 할인이 추천인 다음 결제에 자동 적용됨

---

### 6단계 — 대시보드

**목표**: 출근 후 대시보드 하나로 오늘 해야 할 일이 전부 보임

**레이아웃 구조**
- 상단 헤더 + 좌측 사이드바 + 메인 콘텐츠 (shadcn Card/Badge/Table/Alert)
- 데스크탑/태블릿 전용 (반응형 불필요)
- 다크모드 토글 (shadcn 기본 지원)

**사이드바 네비게이션**
- 대시보드 / 수강생 / 결제 / 시간표 / 보강·패스 / 통계 / 설정

**작업 목록**
- [ ] dashboard_controller#index
- [ ] 상단 헤더
  - 현재 날짜/요일/시각 (실시간)
  - 현재 진행 중인 시간대 표시
  - 알림 벨 (개근 달성 / 등원하원 미체크 / 기타 즉각 알림)
  - 다크모드 토글 버튼

- [ ] ① 지금 이 순간 섹션 (Turbo Stream, 가장 크게)
  - 현재 시간대 수업 중인 수강생 목록 (선생님별)
  - 등원 미체크: 빨간 Badge 강조 (정각 지나도 checked_in_at nil)
  - 하원 미체크: 주황 Badge 강조 (55분 지나도 checked_out_at nil)
  - 현재 시간대 주차 필요 대수 (has_car 기반 자동 계산)

- [ ] ② 오늘 해야 할 일 섹션 (탭 구성)
  - **결제 탭**: 우선순위별 결제 대상
    - 빨간: "홍길동 — 클린 예약금, 오늘 첫수업 완납 필요"
    - 주황: "김철수 — 기타 잔금 미납"
    - 파란: "박영희 — 클린 다음 결제 예정 (수업 후)"
  - **연락 탭**: 오늘 연락할 대상 (유형별 Badge + 완료 체크 버튼)
    - 복귀예정 / 후기기한 / 상품권만료 / 등록대기 / 연락두절
  - **확인 탭**: 동의서·전직서 미수령 / 마이너스 수업 중인 수강생

- [ ] ③ 오늘 전체 시간표 섹션
  - 선생님별 탭 전환
  - 시간대별 슬롯 테이블 (정규 + 보강 합산)
  - 슬롯 3명 풀: 초록 배경
  - 보강 수강생: 별도 색상 + `홍길동(보/무)` 표기
  - 브레이크타임: 회색 비활성 행
  - 오늘 첫수업/복귀 수강생 표기

- [ ] ④ 오늘 마감 요약 섹션
  - 당일 결제 건수 + 합산 금액 (fully_paid: true 실시간 집계)
  - 당일 휴원 수 (시작전 / 3개월이하 / 3개월초과)
  - 당일 퇴원 / 복귀 수
  - 개근 달성자 목록
  - 마감 톡 생성 버튼 → 자동 완성 텍스트 + 복사 버튼

**완료 기준**
- 출근 후 대시보드 하나로 오늘 해야 할 일이 전부 보임
- 출석 처리 시 ① 섹션 실시간 갱신
- 다크모드 토글 작동

---

### 7단계 — 통계 및 마감 자동화

**목표**: 마감 업무 자동화

**작업 목록**
- [ ] 일별 자동 집계
  - 클래스별 결제 수
  - 첫 결제 / 추가 결제 / 결제 개월 수별 분류
    - 첫 결제 기준: 해당 enrollment의 payments 중 가장 첫 번째 (order by created_at)
    - 추가 결제: 두 번째 이후 payment
  - 당일 휴원 수 (시작 전 / 3개월 이하 / 3개월 초과)
    - 통계 기입 기준: payments.fully_paid = true 또는 refunded = true 완료 시점
  - 당일 퇴원 / 복귀 / 연락할 완료 수
  - 오또 선생님 재원자 수 (클린/비클린 구분)
- [ ] 마감 톡 자동 생성
  - 숫자 항목 자동 채움
  - 특이사항 텍스트 입력란
  - 익일 결제 리스트 자동 포함
  - 익일 보강 리스트 자동 포함
  - 복사 버튼 (카카오톡 붙여넣기용)
- [ ] 월말 결산
  - 월별 매출 자동 집계 (payments.amount 기준, fully_paid: true)

**완료 기준**
- 마감 톡 화면에서 숫자 자동 채워지고 특이사항만 입력하면 됨

---

---

## 백그라운드 잡 (Solid Queue)

### 일별 스케줄 잡 (매일 자정 실행)
- `ReviewDueCheckJob`: review_due 도래 + review_url 미입력 수강생 → 연락할 자동 등록
- `GiftVoucherExpiryJob`: gift_voucher expires_at 1개월 전 수강생 → contact_due 자동 등록
- `WaitingExpiryJob`: waiting_expires_at 도래 + fully_paid: false 수강생
  → 미결제 Schedule 자동 삭제, enrollment.status → dropout, 상담원 알림
- `ContactDueJob`: contact_due 당일 도래 수강생 → 연락할 리스트 자동 등록
- `UnpaidLeaveJob`: 연장결제 연락두절 수강생 → 상담원 알림 (휴원 수동 처리 유도)

### 수업 시간대별 잡 (매 정시 실행)
- `AttendanceCheckJob`: 매 정시에 실행, 해당 시간대 Schedule 등원/하원 체크
  - 정각: 등원 미체크(checked_in_at nil) 수강생 → 대시보드 강조 표시
  - 55분: 하원 미체크(checked_out_at nil) 수강생 → 대시보드 강조 표시 + 상담원 알림
  - 실행 시간: 월 14:00~17:55, 화~일 13:00~21:55
  - 브레이크타임(18:00~18:55) 제외

---

## 개발 우선순위 요약

| 단계 | 내용 | 핵심 기술 포인트 |
|---|---|---|
| 1단계 | 수강생 + Enrollment + 결제 + 스케줄 자동 생성 | after_create callback, calculate_nth_lesson_date |
| 2단계 | 출결 시스템 + 키패드 | Turbo Stream, N클래스 선택 화면, 오류 감지 |
| 3단계 | 선생님별 시간표 | slot_count 3명 제한, has_car 주차 계산 |
| 4단계 | 보강/패스 관리 | makeup_available_range, 믹싱 승인 플로우 |
| 5단계 | 자동 계산 모듈 | Schedule 집계 기반 전체 자동화 |
| 6단계 | 대시보드 | 전체 데이터 종합 실시간 표시 |
| 7단계 | 통계/마감 | 마감 톡 자동 생성 |
