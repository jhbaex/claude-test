#!/usr/bin/env bash
# 문서 규칙 ON/OFF 전환. 설정은 프로젝트 루트 .claude/todo-guard.json 에 둔다.
#   사용: doc-toggle.sh on | off | status
CONF=".claude/todo-guard.json"

state() {
  if [ ! -f "$CONF" ]; then echo "ON"; return; fi
  if grep -q '"docRules"[[:space:]]*:[[:space:]]*false' "$CONF"; then echo "OFF"; else echo "ON"; fi
}

case "$1" in
  on)
    mkdir -p .claude
    printf '{\n  "docRules": true\n}\n' > "$CONF"
    echo "[todo-guard] 문서 규칙 ON" ;;
  off)
    mkdir -p .claude
    printf '{\n  "docRules": false\n}\n' > "$CONF"
    echo "[todo-guard] 문서 규칙 OFF" ;;
  *)
    echo "$(state)" ;;
esac
