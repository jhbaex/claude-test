#!/usr/bin/env bash
# 전역 ~/.claude/CLAUDE.md 에 「세션 밖 폴더」 규칙이 있는지 보고, 없으면 넣는다.
#
# 왜 스킬이 챙기나
#   배너 규칙은 세팅하지 않은 새 폴더에서도 지켜져야 한다. 그래서 스킬 안이 아니라
#   전역 CLAUDE.md 에 둔다. 다만 새 PC·새 계정에서는 그 파일이 비어 있으므로,
#   「투두가드 세팅해줘」 한 마디에 전역 규칙까지 갖춰지게 한다.
#
# 사용: ensure-global-rule.sh [check|install]
#   check    있으면 0, 없으면 1
#   install  없을 때만 덧붙임 (이미 있으면 건드리지 않음)

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$SKILL_DIR/rules/outside-rule.md"
DST="$HOME/.claude/CLAUDE.md"
MARK="세션 밖 폴더에서 작업중"

has_rule() {
  [ -f "$DST" ] && grep -q "$MARK" "$DST"
}

case "${1:-check}" in
  check)
    if has_rule; then
      echo "[todo-guard] 전역 규칙 있음 - ~/.claude/CLAUDE.md"
      exit 0
    fi
    echo "[todo-guard] 전역 규칙 없음. ensure-global-rule.sh install 로 넣으십시오."
    exit 1
    ;;
  install)
    if has_rule; then
      echo "[todo-guard] 전역 규칙이 이미 있음. 건드리지 않음."
      exit 0
    fi
    [ -f "$SRC" ] || { echo "[todo-guard] 규칙 원본 없음: $SRC" >&2; exit 1; }
    mkdir -p "$(dirname "$DST")"
    # 되돌릴 수단부터 만든다
    if [ -f "$DST" ]; then
      cp "$DST" "$DST.bak-$(date +%Y%m%d-%H%M%S)"
      printf '\n' >> "$DST"
    else
      printf '# 전역 규칙\n\n' > "$DST"
    fi
    cat "$SRC" >> "$DST"
    echo "[todo-guard] 전역 규칙을 넣었습니다 - $DST"
    echo "  (기존 파일은 .bak-날짜 로 남겨 두었습니다)"
    exit 0
    ;;
  *)
    echo "사용: ensure-global-rule.sh [check|install]" >&2
    exit 2
    ;;
esac
