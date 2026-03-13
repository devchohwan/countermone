# Claude Code Project Setup

## 구현 규칙 (항상 따를 것)
* **"설명 먼저"를 요청하면 절대 코딩하지 마라** — "어떻게 할지 먼저 얘기해봐", "설명해봐" 등의 말이 있으면 설명만 하고 반드시 확인 후 구현할 것
* **전부 구현해라** — 절반만 하거나 TODO 남기지 말 것
* **작업/단계 완료 시 계획 문서에 완료 표시** — TaskUpdate로 completed 처리
* **모든 작업이 완료될 때까지 멈추지 마라** — 중간에 사용자 확인 없이 끝까지 진행
* **any / unknown 타입 사용 금지** — Ruby에서는 untyped 변수나 Object 남용 금지
* **기능 완성 후 반드시 작동 검사** — curl/rails runner로 실제 동작 확인, 단순 페이지 연결이 아닌 의도대로 완벽히 작동하는지 검증. 테스트 데이터가 없으면 rails runner로 직접 생성한 뒤 검증하고, 검증 후 테스트 데이터는 삭제한다
* **테스트 데이터는 실제 데이터 규칙 안에서 생성** — 임의 금액/시간 사용 금지. 반드시 PricePlan, 기존 enrollment의 lesson_time 등 실제 DB에 있는 값을 조회해서 그대로 사용할 것
* **모든 경우의 수를 따져라** — 무언가를 분석하거나 구현할 때 모든 순열·조합·경우의 수를 빠짐없이 나열하고, 각각이 올바르게 처리되는지 확인한 뒤 답할 것

## 라이브 서버 백업 확인
* "라이브 서버 백업 확인"이라는 요청이 오면 아래 명령어로 확인한다:
  ```bash
  ssh -i ~/monemusic root@115.68.195.125 "ls -lt /root/backups/portal_monemusic/ | head -5"
  ```

## Version Control
* Whenever code changes are made, you must record a one-line description with emoji in korean of the change in `.commit_message.txt` with Edit Tool.
   - Read `.commit_message.txt` first, and then Edit.
   - Overwrite regardless of existing content.
   - If it was a git revert related operation, make the .commit_message.txt file empty.
