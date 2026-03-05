# 모네뮤직 카운터 관리시스템 — 구현 현황

## 기술 스택
- **백엔드**: Ruby on Rails 8.0.4 / Ruby 3.4.5
- **DB**: PostgreSQL (socket: /var/run/postgresql, user: cho)
- **프론트엔드**: ERB + Hotwire (Turbo + Stimulus)
- **CSS**: Tailwind CSS
- **인증**: Rails 8 Authentication Generator
- **백그라운드 잡**: Solid Queue
- **서버**: Puma (localhost:3000)

---

## 단계별 구현 현황

| 단계 | 내용 | 상태 |
|------|------|------|
| 1단계 | 수강생 + Enrollment + 결제 + 스케줄 자동 생성 | ✅ 완료 |
| 2단계 | 출결 시스템 + 키패드 | ✅ 완료 |
| 3단계 | 선생님별 시간표 | ✅ 완료 |
| 4단계 | 보강/패스 관리 | ✅ 완료 |
| 5단계 | 자동 계산 모듈 | ✅ 완료 |
| 6단계 | 대시보드 | ✅ 완료 |
| 7단계 | 통계/마감 자동화 | ✅ 완료 |

---

## 모델 (DB 테이블)

### Teacher (선생님)
- 필드: `name`
- 관계: TeacherSubject, Enrollment, Schedule, BreaktimeOpening
- 상수: `SUBJECTS = %w[클린보컬 언클린보컬 기타 작곡 믹싱]`

### TeacherSubject (선생님-과목 매핑)
- 필드: `teacher_id`, `subject`

### PricePlan (가격표)
- 필드: `subject`, `months`, `amount`, `active`
- 메서드: `self.find_amount(subject, months)` — 가격 자동 조회

### Student (수강생)
- 필드: `name`, `phone`, `attendance_code`, `status`, `rank`, `has_car`, `consent_form`, `second_transfer_form`, `cover_recorded`, `contact_due`, `waiting_expires_at`, `referrer_id`, 후기/인터뷰/상품권 플래그 등
- status: `active / leave / dropout / pending / unregistered`
- rank: `first / second` (2차 전직서 수령 시 자동 변경)
- 출결 코드: 전화번호 뒷 4자리 (재원 수강생 간 유일, 중복 시 5자리/중간자리)
- 메서드: `remaining_lessons_for(enrollment)`, `consecutive_weeks_for(enrollment)`, `total_attended_weeks_for(enrollment)`
- 콜백: `before_save :update_rank_from_transfer_form`

### Enrollment (클래스 등록)
- 필드: `student_id`, `teacher_id`, `subject`, `lesson_day`, `lesson_time`, `status`, `remaining_on_leave`, `minus_lesson_count`, `attendance_event_pending`
- status: `active / leave / dropout`
- 검증: 요일별 운영시간 (월 14:00~17:00, 화~일 13:00~21:00), 선생님 담당 과목
- 메서드: `leave!`, `return!`, `dropout!`, `returnable?`

### Payment (결제)
- 필드: `payment_type`, `subject`, `months`, `total_lessons`, `amount`, `payment_method`, `deposit_amount`, `balance_amount`, `fully_paid`, `refunded`, `refund_amount`, `starts_at`
- payment_type: `new / deposit`
- payment_method: `card / transfer / cash`
- 콜백: `after_create :generate_schedules` (스케줄 자동 생성), 개근/지인 할인 자동 적용, 후기 기한 자동 설정, 완납 시 휴원 복귀
- 메서드: `ends_at` (동적 계산), `refund_amount_calculated`

### Schedule (수업 스케줄)
- 필드: `lesson_date`, `lesson_time`, `subject`, `status`, `sequence`, `makeup_date`, `makeup_time`, `makeup_teacher_id`, `makeup_approved`, `pass_reason`
- status: `scheduled / attended / late / deducted / pass / emergency_pass / makeup_scheduled / makeup_done / minus_lesson`
- 메서드: `makeup_available_range` (보강 가능 기간), `self.slot_count(teacher_id, subject, date)` (최대 3명)

### Attendance (출석 기록)
- 필드: `checked_in_at`, `checked_out_at`, `error_type`
- error_type: `double_checkin / missing_class / old_payment / expired_date`

### Discount (할인)
- 필드: `discount_type`, `amount`, `memo`
- discount_type: `multi_month / referral / multi_class / review / interview / attendance_event`

### GiftVoucher (상품권)
- 필드: `issued_at`, `used`, `used_class`, `expires_at`
- 24회 출석 달성 시 자동 생성

### BreaktimeOpening (브레이크타임 개방)
- 필드: `teacher_id`, `date`, `created_by`

---

## 컨트롤러

### StudentsController
- `index` — 수강생 목록 (상태별 필터, 이름 검색)
- `show` — 상세 (enrollments + payments + schedules)
- `new / create` — 수강생 + enrollment + payment 동시 생성 (transaction)
- `edit / update` — 정보 수정
- `destroy` — 삭제
- `leave / return / dropout` — 상태 변경
- `check_attendance_code` — 출결 코드 중복 체크 (AJAX)

### EnrollmentsController
- `show / new / create / edit / update / destroy`
- `leave / return / dropout` — 클래스별 상태 변경

### PaymentsController
- `index` — 최근 결제 50건
- `show / new / create`
- `refund` — 환불 처리
- `pay_balance` — 잔금 납부 → `fully_paid = true`
- 자동 할인: 다개월 할인, 중복 클래스 할인 (클래스수-1 × 5만원)

### SchedulesController
- `index` — 날짜별 스케줄 목록
- `show`
- `attend / late / absent / deduct` — 출결 처리
- `pass / emergency_pass` — 패스 처리 (당일/믹싱 불가, 개근 리셋)
- `makeup / complete_makeup` — 보강 배정/완료 (가능 기간 + 슬롯 체크)
- 자동 체크: 12주 개근 → `attendance_event_pending = true`, 24회 → 상품권 생성

### DashboardController
- `index` — 종합 대시보드
  1. 현재 시간대 수업 중인 수강생
  2. 오늘 결제 예정자 (우선순위별)
  3. 연락할 리스트 (contact_due / return_at / waiting_expires_at)
  4. 마이너스 수업 수강생
  5. 동의서/전직서 미수령
  6. 오늘 마감 집계 (결제/휴퇴원/복귀/개근)

### KeypadController (인증 스킵)
- `index` — 출석 키패드 UI
- `checkin` — 출결 코드 입력 → 등원 처리 (지각 자동 판단)
- `checkout` — 하원 처리

### TimetableController
- `index` — 선생님 목록 → 첫 선생님 리다이렉트
- `show` — 선생님별 주간 시간표 (정규+보강, 브레이크타임 표시)

### StatisticsController
- `index` — 일별 통계
- `daily` — 특정 날짜 통계 (첫 결제/추가 결제 자동 분류)
- `monthly` — 월별 매출

### PricePlansController
- 가격표 CRUD (삭제는 soft delete)

---

## 라우트 구조

```
/                          → dashboard#index
/students                  → 수강생 목록
/students/:id/leave|return|dropout
/students/:id/enrollments  → nested (shallow)
/enrollments/:id/leave|return|dropout
/payments                  → 결제 목록
/payments/:id/refund|pay_balance
/schedules/:id/attend|deduct|pass|emergency_pass|makeup|complete_makeup
/timetable                 → 시간표
/timetable/:teacher_id
/keypad                    → 출석 키패드 (인증 없음)
/keypad/checkin|checkout
/statistics                → 통계
/statistics/daily|monthly
/price_plans               → 가격표 CRUD
```

---

## 할인 체계

| 유형 | 조건 | 금액 |
|------|------|------|
| 다개월 | 3~4개월 일시 결제 | (1개월×개월수) - 실제가격 |
| 지인 | 추천인 & 피추천인 | 각 5만원 |
| 중복 클래스 | 2개 이상 클래스 | (클래스수-1) × 5만원 |
| 후기 | 3개월 후 후기 작성 | 5만원 |
| 인터뷰 | 6개월 후 촬영 완료 | 5만원 |
| 개근이벤트 | 12주 개근 | 1회 무료 |

---

## 핵심 비즈니스 로직

### 데이터 흐름
```
결제(Payment) 생성
    ↓ after_create
스케줄(Schedule) 자동 생성 (4주분)
    ↓
할인(Discount) 자동 적용
    ↓
시간표/대시보드/통계 자동 반영
```

### 보강/패스 규칙
- **보강 가능 기간**: 이전 수업 다음날 ~ 다음 수업 전날
- **슬롯**: 정규+보강 합산 최대 3명
- **패스**: 1개월당 1회, 당일/믹싱 불가, 사용 시 개근 리셋
- **믹싱 보강**: 담당 선생님 승인 필요

### 휴원/복귀 규칙
- 휴원 시: 미래 스케줄 삭제 + `remaining_on_leave` 보존
- 복귀 조건: `fully_paid = true` 필수
- 복귀 시: 출결 코드 중복 자동 체크

### 출결 코드 규칙
- 기본: 전화번호 뒷 4자리
- 재원 수강생 간 유일 보장
- 중복 시: 5자리 → 중간자리 순으로 자동 확장

---

## 백그라운드 잡 (Solid Queue, 자정 실행)
- `ReviewDueCheckJob` — review_due 도래 + 미작성 알림
- `GiftVoucherExpiryJob` — 상품권 만료 1개월 전 알림
- `WaitingExpiryJob` — waiting_expires_at 도래 + 미결제 처리
- `AttendanceCheckJob` — 매 정시 등원/하원 미체크 감지
