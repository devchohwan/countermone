# 보안 종합 해결책 (counter.monemusic.com)

**작성일**: 2026-03-10
**기반**: 보안 현황 보고서 + 30가지 공격 벡터 심층 방어 분석
**대상**: 컨트롤러 16개, 모델 8개, 설정 파일 전체

---

## 진단 요약

기존 보고서 종합 점수 **7.7/10**. 인증/CSRF/SQL Injection 등 기본 방어는 잘 되어 있으나, 아래 영역에서 실질적 침투 경로가 존재합니다.

| 위험도 | 항목 | 현재 상태 |
|--------|------|-----------|
| 🔴 치명 | 키패드 Rate Limiting 없음 | 브루트포스로 전체 출석 위조 가능 |
| 🔴 치명 | .env 시크릿 평문 저장 | RAILS_MASTER_KEY 노출 시 전체 암호화 무력화 |
| 🔴 치명 | Attendance Code 예측 가능 | 전화번호 뒷4자리 = 사실상 공개 정보 |
| 🟡 중간 | SSH root 배포 | 서버 탈취 시 전체 권한 획득 |
| 🟡 중간 | CSP 헤더 미설정 | XSS 공격 시 보조 방어선 없음 |
| 🟡 중간 | 모니터링 부재 | 침투 당해도 인지 불가 |

---

## 🔴 즉시 조치 (1일 이내)

### 1. 키패드 Rate Limiting 추가

**위협**: `/keypad/checkin`과 `/keypad/checkout`에 인증 없이 무제한 POST 가능. attendance_code가 4자리 숫자이므로 최대 10,000번 시도면 모든 수강생 출석 위조 가능.

```ruby
# app/controllers/keypad_controller.rb
class KeypadController < ApplicationController
  rate_limit to: 5, within: 1.minute, by: -> { request.remote_ip }, with: -> {
    render json: { error: "Too many attempts. Please wait." }, status: :too_many_requests
  }

  # 추가: 연속 실패 시 IP 차단 로직
  before_action :check_blocked_ip

  private

  def check_blocked_ip
    cache_key = "keypad_blocked:#{request.remote_ip}"
    if Rails.cache.read(cache_key)
      render json: { error: "Temporarily blocked" }, status: :forbidden
      return
    end
  end

  def record_failed_attempt
    cache_key = "keypad_failures:#{request.remote_ip}"
    failures = Rails.cache.increment(cache_key, 1, expires_in: 10.minutes)
    if failures && failures >= 15
      Rails.cache.write("keypad_blocked:#{request.remote_ip}", true, expires_in: 30.minutes)
      Rails.logger.warn("[SECURITY] IP #{request.remote_ip} blocked: keypad brute force")
    end
  end
end
```

### 2. Attendance Code를 랜덤 생성으로 변경

**위협**: 전화번호 마지막 4자리는 사실상 공개 정보. 지인, SNS, 명함 등에서 쉽게 확보 가능.

```ruby
# app/models/student.rb (또는 해당 모델)
class Student < ApplicationRecord
  before_create :generate_attendance_code

  private

  def generate_attendance_code
    loop do
      self.attendance_code = SecureRandom.alphanumeric(8).downcase
      break unless Student.exists?(attendance_code: attendance_code)
    end
  end
end
```

**기존 데이터 마이그레이션**:

```ruby
# db/migrate/XXXXXX_regenerate_attendance_codes.rb
class RegenerateAttendanceCodes < ActiveRecord::Migration[8.0]
  def up
    Student.find_each do |student|
      loop do
        code = SecureRandom.alphanumeric(8).downcase
        unless Student.where.not(id: student.id).exists?(attendance_code: code)
          student.update_column(:attendance_code, code)
          break
        end
      end
    end
  end
end
```

**변경 후 수강생에게 새 코드 안내 필요** — 관리자 페이지에서 각 수강생의 새 코드를 확인/전송하는 기능 추가 권장.

### 3. 시크릿 재발급 및 관리 방식 변경

**위협**: `.env`에 평문 저장된 `RAILS_MASTER_KEY`가 노출되면 `credentials.yml.enc`의 모든 시크릿이 복호화됨. git 히스토리에 한 번이라도 커밋됐다면 이미 노출된 것으로 간주해야 함.

```bash
# Step 1: git 히스토리 확인
git log --all --oneline -- .env
git log --all --oneline -- config/master.key

# Step 2: 히스토리에 있다면 → 키 전체 재발급
# (히스토리에 없어도 예방 차원에서 재발급 권장)

# Step 3: RAILS_MASTER_KEY 재발급
rm config/credentials.yml.enc
EDITOR="code --wait" bin/rails credentials:edit
# → 새 master.key가 자동 생성됨

# Step 4: KAMAL_REGISTRY_PASSWORD 재발급
# Docker Hub / Registry에서 새 토큰 발급

# Step 5: 서버에 환경변수로 주입 (Kamal 사용 시)
```

```yaml
# config/deploy.yml (Kamal)
env:
  clear:
    RAILS_ENV: production
  secret:
    - RAILS_MASTER_KEY
    - KAMAL_REGISTRY_PASSWORD
```

```bash
# 서버에 시크릿 설정 (Kamal 2)
kamal env push

# 또는 서버에서 직접 설정
# /etc/environment 또는 systemd service의 Environment= 에 설정
```

**git 히스토리에서 .env 완전 제거** (히스토리에 있었던 경우):

```bash
# git-filter-repo 사용 (권장)
pip install git-filter-repo
git filter-repo --path .env --invert-paths

# 이후 force push
git push --force --all
```

---

## 🟡 단기 조치 (1주 이내)

### 4. SSH 배포 사용자 변경

**위협**: root로 배포하면, 배포 과정에서 취약점이 발생할 경우 서버 전체 권한 탈취.

```bash
# 서버에서 전용 배포 사용자 생성
sudo adduser deploy
sudo usermod -aG docker deploy

# SSH 키 설정
sudo mkdir -p /home/deploy/.ssh
sudo cp ~/.ssh/authorized_keys /home/deploy/.ssh/
sudo chown -R deploy:deploy /home/deploy/.ssh
sudo chmod 700 /home/deploy/.ssh
sudo chmod 600 /home/deploy/.ssh/authorized_keys

# root SSH 로그인 비활성화
sudo sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

```yaml
# config/deploy.yml (Kamal)
servers:
  web:
    hosts:
      - your-server-ip
    options:
      user: deploy   # root → deploy로 변경
```

### 5. CSP 헤더 설정

**위협**: XSS 공격 성공 시 악성 스크립트가 외부로 데이터를 전송하는 것을 막는 보조 방어선이 없음.

```ruby
# config/initializers/content_security_policy.rb
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, "https://fonts.gstatic.com"
    policy.img_src     :self, :data, "https:"
    policy.object_src  :none
    policy.script_src  :self
    policy.style_src   :self, :unsafe_inline  # Tailwind 등 인라인 스타일 필요 시
    policy.connect_src :self
    policy.frame_ancestors :none              # Clickjacking 방어
    policy.base_uri    :self
    policy.form_action :self
  end

  # 위반 시 리포트 수집 (선택)
  config.content_security_policy_report_only = false
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
end
```

### 6. 보안 헤더 종합 설정

```ruby
# config/application.rb 또는 initializer
config.action_dispatch.default_headers.merge!(
  "X-Frame-Options" => "DENY",
  "X-Content-Type-Options" => "nosniff",
  "X-XSS-Protection" => "0",           # 최신 브라우저에서는 CSP가 대체
  "Referrer-Policy" => "strict-origin-when-cross-origin",
  "Permissions-Policy" => "camera=(), microphone=(), geolocation=()"
)
```

### 7. 비밀번호 리셋 토큰 보안 강화

**위협**: 공개 엔드포인트 `/passwords/*`에서 비밀번호 리셋 토큰이 예측 가능하거나 만료되지 않으면 계정 탈취 가능.

```ruby
# 확인 필요 사항:
# 1. 리셋 토큰에 만료 시간이 있는가?
# 2. 사용 후 토큰이 무효화되는가?
# 3. 리셋 요청에도 rate limiting이 있는가?

# PasswordsController에 rate limiting 추가
class PasswordsController < ApplicationController
  rate_limit to: 3, within: 5.minutes, only: [:create], by: -> { request.remote_ip }, with: -> {
    redirect_to new_password_path, alert: "Too many requests. Please wait."
  }
end
```

### 8. 회원가입 엔드포인트 보호

**위협**: `/signup`에 rate limiting이 없으면 대량의 가입 요청으로 관리자에게 승인 알림 폭탄 가능 (DoS의 일종).

```ruby
# app/controllers/registrations_controller.rb (또는 해당 컨트롤러)
class RegistrationsController < ApplicationController
  rate_limit to: 3, within: 10.minutes, only: [:create], by: -> { request.remote_ip }, with: -> {
    redirect_to signup_path, alert: "Too many sign-up attempts."
  }
end
```

---

## 🟢 중기 조치 (2-4주)

### 9. Rack::Attack 종합 설정

개별 컨트롤러의 `rate_limit`과 별도로, 애플리케이션 전체에 대한 방어를 설정합니다.

```ruby
# Gemfile
gem "rack-attack"

# config/initializers/rack_attack.rb
class Rack::Attack
  ### 전체 요청 제한 ###
  throttle("req/ip", limit: 300, period: 5.minutes) do |req|
    req.ip
  end

  ### 로그인 브루트포스 (IP 기반) ###
  throttle("logins/ip", limit: 5, period: 60.seconds) do |req|
    req.ip if req.path == "/session" && req.post?
  end

  ### 로그인 브루트포스 (이메일 기반) ###
  throttle("logins/email", limit: 5, period: 60.seconds) do |req|
    if req.path == "/session" && req.post?
      req.params.dig("email_address")&.downcase&.strip
    end
  end

  ### 키패드 브루트포스 ###
  throttle("keypad/ip", limit: 5, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/keypad") && req.post?
  end

  ### 비밀번호 리셋 ###
  throttle("password_reset/ip", limit: 3, period: 5.minutes) do |req|
    req.ip if req.path.start_with?("/passwords") && req.post?
  end

  ### 회원가입 ###
  throttle("signup/ip", limit: 3, period: 10.minutes) do |req|
    req.ip if req.path == "/signup" && req.post?
  end

  ### 차단 시 응답 ###
  self.throttled_responder = lambda do |matched, period, limit, request|
    now = Time.now.utc
    retry_after = (request.env["rack.attack.match_data"] || {})[:period]
    [
      429,
      {
        "Content-Type" => "application/json",
        "Retry-After" => retry_after.to_s
      },
      [{ error: "Rate limit exceeded. Retry later." }.to_json]
    ]
  end
end
```

### 10. 모니터링 및 알림 시스템

**위협**: 현재 침투 당해도 인지할 수 없음. 로그를 수집하고 이상 행위를 탐지하는 체계가 필요합니다.

```ruby
# config/initializers/security_monitoring.rb

# Rack::Attack 이벤트 로깅
ActiveSupport::Notifications.subscribe(/rack\.attack/) do |name, start, finish, id, payload|
  req = payload[:request]
  match_type = req.env["rack.attack.match_type"]
  match_data = req.env["rack.attack.match_data"]

  if match_type == :throttle
    Rails.logger.warn(
      "[SECURITY] Rate limit hit: " \
      "ip=#{req.ip} path=#{req.path} " \
      "matched=#{req.env['rack.attack.matched']} " \
      "count=#{match_data&.dig(:count)}"
    )

    # Slack/Discord 알림 (선택)
    # SecurityNotifier.rate_limit_alert(req.ip, req.path)
  end
end
```

```ruby
# app/models/concerns/auditable.rb
# 주요 모델 변경 이력 추적
module Auditable
  extend ActiveSupport::Concern

  included do
    after_create  { log_audit("create") }
    after_update  { log_audit("update") }
    after_destroy { log_audit("destroy") }
  end

  private

  def log_audit(action)
    Rails.logger.info(
      "[AUDIT] #{self.class.name}##{id} #{action} " \
      "by=#{Current.user&.id} ip=#{Current.ip_address} " \
      "changes=#{saved_changes.except('updated_at').keys}"
    )
  end
end
```

```ruby
# app/models/application_record.rb
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end

# 출석 기록 등 민감 모델에 적용
# app/models/attendance.rb
class Attendance < ApplicationRecord
  include Auditable
end
```

### 11. 세션 보안 강화

```ruby
# config/initializers/session_store.rb
Rails.application.config.session_store :cookie_store,
  key: "_counter_session",
  secure: Rails.env.production?,
  httponly: true,
  same_site: :lax,
  expire_after: 12.hours    # 세션 만료 시간 설정

# 로그인 성공 시 세션 재생성 (Session Fixation 방어)
# app/controllers/sessions_controller.rb
class SessionsController < ApplicationController
  def create
    # ... 인증 로직 ...
    if authenticated
      reset_session                          # 기존 세션 무효화
      session[:user_id] = user.id            # 새 세션에 사용자 할당
      # ...
    end
  end
end
```

### 12. CORS 설정 (API가 있는 경우)

```ruby
# Gemfile
gem "rack-cors"

# config/initializers/cors.rb
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins "counter.monemusic.com"    # 자기 도메인만 허용
    resource "*",
      headers: :any,
      methods: [:get, :post, :patch, :delete],
      credentials: true
  end
end
```

---

## 🔵 CI/CD 보안 파이프라인

### 13. GitHub Actions 보안 자동화

```yaml
# .github/workflows/security.yml
name: Security Pipeline
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  brakeman:
    name: Static Analysis (Brakeman)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.3"
      - run: gem install brakeman
      - run: brakeman --no-pager -w2 --exit-on-warn -o brakeman-report.json
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: brakeman-report
          path: brakeman-report.json

  bundle-audit:
    name: Dependency Audit
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.3"
          bundler-cache: true
      - run: gem install bundler-audit
      - run: bundle audit check --update

  ruby-audit:
    name: Ruby Version Audit
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.3"
      - run: gem install ruby_audit
      - run: ruby-audit check
```

### 14. 배포 전 로컬 체크 스크립트

```bash
#!/bin/bash
# bin/security_check.sh
set -e

echo "=== Brakeman (정적 분석) ==="
brakeman --no-pager -w2 --exit-on-warn

echo ""
echo "=== bundler-audit (gem 취약점) ==="
bundle audit check --update

echo ""
echo "=== 시크릿 노출 확인 ==="
# .env, master.key가 git에 포함되어 있는지 확인
if git ls-files --error-unmatch .env 2>/dev/null; then
  echo "⚠️  WARNING: .env is tracked by git!"
  exit 1
fi
if git ls-files --error-unmatch config/master.key 2>/dev/null; then
  echo "⚠️  WARNING: master.key is tracked by git!"
  exit 1
fi

echo ""
echo "=== html_safe / raw 사용 확인 ==="
count=$(grep -r "html_safe\|\.raw\b" app/views/ --include="*.erb" -l 2>/dev/null | wc -l)
if [ "$count" -gt 0 ]; then
  echo "⚠️  WARNING: html_safe/raw found in $count view files:"
  grep -r "html_safe\|\.raw\b" app/views/ --include="*.erb" -l
fi

echo ""
echo "✅ Security check passed"
```

```bash
chmod +x bin/security_check.sh
```

---

## 🟣 공격 벡터별 현재 상태 및 조치 매트릭스

기존 보고서에서 다루지 않았지만 확인/조치가 필요한 항목들입니다.

### 확인 필요 항목

| # | 공격 벡터 | 현재 추정 상태 | 조치 |
|---|-----------|---------------|------|
| 1 | Open Redirect | 미확인 | `redirect_to`에 사용자 입력이 들어가는 곳 전수 검사 |
| 2 | SSRF | 미확인 | 외부 URL을 fetch하는 기능이 있다면 ssrf_filter gem 적용 |
| 3 | 역직렬화 | 미확인 | `Marshal.load`, `YAML.load` 사용 여부 검사 |
| 4 | Clickjacking | CSP 미설정 | 위 CSP 설정으로 해결 (`frame-ancestors: none`) |
| 5 | Host Header Injection | 미확인 | `config.hosts << "counter.monemusic.com"` 설정 |
| 6 | Timing Attack | 미확인 | 토큰 비교 시 `secure_compare` 사용 여부 확인 |
| 7 | Action Cable | 미확인 | 사용 중이라면 인증 로직 확인 |
| 8 | 메모리 내 민감정보 | 해당 없음 (Ruby GC) | 장기 캐시에 개인정보 저장하지 않도록 주의 |

### Host Header 설정

```ruby
# config/environments/production.rb
config.hosts << "counter.monemusic.com"
config.hosts << /.*\.monemusic\.com/   # 서브도메인 필요 시

# ActionMailer (비밀번호 리셋 링크 등)
config.action_mailer.default_url_options = { host: "counter.monemusic.com", protocol: "https" }
```

---

## 구현 우선순위 로드맵

### Phase 1: 긴급 (오늘)
1. ✅ KeypadController에 rate_limit 추가
2. ✅ attendance_code를 SecureRandom 기반으로 변경 + 마이그레이션
3. ✅ git 히스토리에서 .env 노출 여부 확인 → 키 재발급

### Phase 2: 이번 주
4. SSH 배포 사용자 변경 (root → deploy)
5. CSP 헤더 + 보안 헤더 설정
6. config.hosts 설정
7. 비밀번호 리셋 / 회원가입 rate limiting
8. 세션 보안 강화 (expire_after, reset_session)

### Phase 3: 2주 이내
9. Rack::Attack 종합 설정
10. 보안 모니터링 (감사 로깅, 이상 행위 탐지)
11. CI/CD에 Brakeman + bundler-audit 연동
12. bin/security_check.sh 로컬 스크립트 도입

### Phase 4: 월간 유지보수
- `bundle audit check --update` 정기 실행
- Brakeman 스캔 결과 리뷰
- 서브도메인/DNS 레코드 감사
- 세션/토큰 만료 정책 점검
- 보안 사고 대응 훈련

---

## 조치 완료 후 예상 점수

| 항목 | 현재 | 목표 |
|------|------|------|
| 인증/인가 | 9/10 | 10/10 |
| 데이터 보호 | 9/10 | 10/10 |
| 입력 검증 | 9/10 | 10/10 |
| Rate Limiting | 6/10 | 9/10 |
| 시크릿 관리 | 5/10 | 9/10 |
| 배포 보안 | 8/10 | 9/10 |
| 모니터링 | 0/10 | 8/10 |
| CI/CD 보안 | 0/10 | 9/10 |
| **종합** | **7.7/10** | **9.3/10** |
