#!/bin/bash
set -e

echo "=== 시크릿 git 추적 확인 ==="
if git ls-files --error-unmatch .env 2>/dev/null; then
  echo "⚠️  WARNING: .env이 git에 포함되어 있습니다!"
  exit 1
fi
if git ls-files --error-unmatch config/master.key 2>/dev/null; then
  echo "⚠️  WARNING: master.key가 git에 포함되어 있습니다!"
  exit 1
fi
echo "✅ 시크릿 파일 git 미추적 확인 완료"

echo ""
echo "=== .env git 히스토리 확인 ==="
count=$(git log --all --oneline -- .env 2>/dev/null | wc -l)
if [ "$count" -gt 0 ]; then
  echo "⚠️  WARNING: .env가 git 히스토리에 ${count}회 포함된 적 있습니다. 키 재발급을 검토하세요."
else
  echo "✅ .env 히스토리 없음"
fi

echo ""
echo "=== html_safe / raw 사용 확인 ==="
matches=$(grep -r "html_safe\|\.raw\b" app/views/ --include="*.erb" 2>/dev/null | grep -v "to_json.html_safe" | wc -l)
if [ "$matches" -gt 0 ]; then
  echo "⚠️  WARNING: html_safe/raw 사용 ${matches}건 (검토 필요):"
  grep -r "html_safe\|\.raw\b" app/views/ --include="*.erb" | grep -v "to_json.html_safe"
else
  echo "✅ html_safe/raw 위험 사용 없음"
fi

echo ""
echo "✅ 보안 체크 완료"
