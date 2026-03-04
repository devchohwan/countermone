#!/bin/bash

# Auto-commit with .commit_message.txt (Bash/Linux)

# git 저장소인지 확인
git rev-parse --is-inside-work-tree > /dev/null 2>&1 || exit 0

# 변경사항이 있는지 확인
changes=$(git status --porcelain)
[ -z "$changes" ] && exit 0

# commit_message.txt 읽기
top=$(git rev-parse --show-toplevel)
msg_file="$top/.commit_message.txt"

[ -f "$msg_file" ] || exit 0
msg=$(cat "$msg_file")
[ -z "$msg" ] && exit 0

# 커밋 실행
git add -A
git commit -F "$msg_file" --quiet
