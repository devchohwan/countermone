#!/bin/bash
# counter DB 백업 스크립트
# 5분마다 실행, 3일(72시간) 보존

set -euo pipefail

BACKUP_DIR="/root/backups/portal_monemusic"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/production_$TIMESTAMP.sqlite3"

# 실행 중인 counter-web 컨테이너 이름 찾기
CONTAINER=$(docker ps --filter "name=counter-web" --format "{{.Names}}" | head -1)
if [ -z "$CONTAINER" ]; then
  echo "[$(date)] ERROR: counter-web 컨테이너가 실행중이지 않습니다." >&2
  exit 1
fi

# 백업 디렉토리 생성
mkdir -p "$BACKUP_DIR"

# 컨테이너 내부에서 sqlite3 .backup으로 일관된 스냅샷 생성
docker exec "$CONTAINER" sqlite3 /rails/storage/production.sqlite3 \
  ".backup /tmp/db_backup_$TIMESTAMP.sqlite3"

# 컨테이너에서 호스트로 복사
docker cp "$CONTAINER:/tmp/db_backup_$TIMESTAMP.sqlite3" "$BACKUP_FILE"

# 컨테이너 내 임시 파일 제거
docker exec "$CONTAINER" rm -f "/tmp/db_backup_$TIMESTAMP.sqlite3"

# gzip 압축
gzip "$BACKUP_FILE"

# 3일(72시간) 이상 된 파일 삭제
find "$BACKUP_DIR" -name "*.sqlite3.gz" -mmin +$((72 * 60)) -delete

echo "[$(date)] 백업 완료: ${BACKUP_FILE}.gz"
