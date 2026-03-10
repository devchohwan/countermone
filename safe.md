# 보안 현황 보고서 (counter.monemusic.com)

**작성일**: 2026-03-10
**조사 범위**: 컨트롤러 16개, 모델 8개, 설정 파일 전체

---

## 종합 평가

| 항목 | 점수 | 비고 |
|------|------|------|
| 인증/인가 | 9/10 | 승인 기반 가입 제어 우수 |
| 데이터 보호 | 9/10 | HTTPS, 암호화된 쿠키 |
| 입력 검증 | 9/10 | Strong Parameters 잘 구현 |
| Rate Limiting | 6/10 | 로그인만 구현, 키패드 미보호 |
| 시크릿 관리 | 5/10 | .env에 평문 저장 위험 |
| 배포 보안 | 8/10 | Docker 최적화, SSH user 개선 필요 |
| **종합** | **7.7/10** | 중상 수준 |

---

## 안전한 항목 (Green)

### 1. 인증 시스템
- 모든 컨트롤러에 `before_action :require_authentication` 적용
- `has_secure_password` bcrypt 기반 비밀번호 암호화
- `approved` 플래그로 관리자 승인 후 가입 활성화
- 세션 쿠키: `httponly: true, same_site: :lax`

### 2. SQL Injection
- 모든 raw query 파라미터화 처리 (`where("DATE(updated_at) = ?", date)` 형식)
- ActiveRecord 자동 파라미터화로 SQL injection 실질적 불가

### 3. CSRF 보호
- Rails 8 기본 CSRF 토큰 활성화
- 모든 POST/PATCH/DELETE 요청에 자동 검증

### 4. Strong Parameters
- 모든 컨트롤러에서 `params.require().permit()` 화이트리스트 방식 사용
- 중첩 속성도 명시적 선언

### 5. HTTPS/SSL
- `config.force_ssl = true` (Rails 레벨 강제)
- Kamal `proxy.ssl: true` (Let's Encrypt 자동 인증서)

### 6. 로그 필터링
- `filter_parameters`에 passw, email, secret, token 등 민감 파라미터 필터링

### 7. Docker 실행
- Non-root 사용자(rails uid=1000)로 컨테이너 실행

---

## 개선 필요 항목 (Yellow)

### 1. Rate Limiting 부분 적용
- **현재**: `SessionsController`만 10회/3분 제한
- **미보호**: `KeypadController` — checkin/checkout 무제한 시도 가능
- **권장**: 키패드에도 `rate_limit to: 5, within: 1.minute` 추가

### 2. Attendance Code 예측 가능
- **현재 생성 방식**: 전화번호 마지막 4자리 기반 (`phone.last(4)`)
- **문제**: 전화번호 알면 100% 유추 가능, 4자리 숫자라 브루트포스 10,000가지 시도면 해결
- **권장**: `SecureRandom.alphanumeric(8)` 랜덤 8자리로 변경

### 3. SSH 배포 사용자
- **현재**: Kamal 배포 시 `user: root` 사용
- **권장**: 전용 배포 사용자 계정 생성

---

## 즉시 조치 필요 항목 (Red)

### 1. 키패드 Rate Limiting 없음
- `/keypad/checkin` 에 인증 없이 무제한 POST 가능
- attendance_code 4자리 브루트포스로 전체 수강생 출석 기록 위조 가능
- **조치**: KeypadController에 rate_limit 추가 또는 IP 기반 차단

### 2. 시크릿 평문 저장
- `.env` 파일에 `RAILS_MASTER_KEY`, `KAMAL_REGISTRY_PASSWORD` 평문 저장
- `.gitignore`에는 포함되어 있으나 git 히스토리에 한 번이라도 커밋됐다면 노출
- **조치**: git 히스토리 확인, 필요 시 키 재발급

---

## 공개 엔드포인트 목록

인증 없이 접근 가능한 URL:

| URL | 설명 | 보호 수단 |
|-----|------|----------|
| GET /session/new | 로그인 페이지 | — |
| POST /session | 로그인 처리 | Rate limit (10/3분) |
| GET /signup | 회원가입 | — |
| POST /signup | 회원가입 처리 | 관리자 승인 필요 |
| GET /passwords/* | 비밀번호 리셋 | 이메일 토큰 |
| GET /keypad | 키패드 화면 | — |
| POST /keypad/checkin | 출석 처리 | attendance_code |
| POST /keypad/checkout | 하원 처리 | attendance_code |

---

## 즉시 조치 우선순위

| 우선순위 | 항목 | 방법 |
|---------|------|------|
| 🔴 높음 | 키패드 Rate Limiting | `rate_limit to: 5, within: 1.minute` |
| 🔴 높음 | .env 시크릿 재발급 | git 히스토리 확인 후 키 교체 |
| 🟡 중간 | Attendance Code 개선 | SecureRandom 기반 변경 |
| 🟡 중간 | 배포 SSH 사용자 변경 | root → 전용 계정 |
| 🟢 낮음 | CSP 헤더 | content_security_policy.rb 활성화 |
