#!/usr/bin/env bash
# 사용자가 허가한 「프로젝트 밖 경로」를 설정에 적는다.
#   사용: allow-outside.sh <경로>
#         allow-outside.sh --list
#
# 사용자 허가 없이 이 스크립트를 부르지 않는다. 부르는 순간 차단이 풀린다.
CONF=".claude/todo-guard.json"

if [ "${1:-}" = "--list" ]; then
  [ -f "$CONF" ] && sed -n 's/.*"allowOutside"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' "$CONF"
  exit 0
fi

TARGET="${1:-}"
[ -z "$TARGET" ] && { echo "사용: allow-outside.sh <경로>" >&2; exit 2; }

# 파일을 주면 그 폴더를 허용한다
if [ -f "$TARGET" ]; then
  TARGET=$(dirname "$TARGET")
fi
TARGET=$(printf '%s' "$TARGET" | sed 's|\\|/|g')

mkdir -p .claude
if [ ! -f "$CONF" ]; then
  printf '{\n  "docRules": true,\n  "allowOutside": ["%s"]\n}\n' "$TARGET" > "$CONF"
  echo "[todo-guard] 허용 경로 추가 - $TARGET"
  exit 0
fi

if grep -q "allowOutside" "$CONF"; then
  if grep -q "\"$TARGET\"" "$CONF"; then
    echo "[todo-guard] 이미 허용된 경로 - $TARGET"
  else
    python - "$CONF" "$TARGET" <<'PY'
import io, json, sys
p, t = sys.argv[1], sys.argv[2]
d = json.load(io.open(p, encoding="utf-8"))
d.setdefault("allowOutside", []).append(t)
io.open(p, "w", encoding="utf-8", newline=chr(10)).write(
    json.dumps(d, ensure_ascii=False, indent=2) + chr(10))
print("[todo-guard] 허용 경로 추가 - " + t)
PY
  fi
else
  python - "$CONF" "$TARGET" <<'PY'
import io, json, sys
p, t = sys.argv[1], sys.argv[2]
d = json.load(io.open(p, encoding="utf-8"))
d["allowOutside"] = [t]
io.open(p, "w", encoding="utf-8", newline=chr(10)).write(
    json.dumps(d, ensure_ascii=False, indent=2) + chr(10))
print("[todo-guard] 허용 경로 추가 - " + t)
PY
fi
