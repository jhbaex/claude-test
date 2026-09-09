#!/usr/bin/env bash
# PreToolUse 훅: 도구가 실제로 실행되기 전에 막는다.
#
# 왜 필요한가
#   SKILL.md 에 「TODO.md 를 덮어쓰지 말 것」이라고 적어도 글일 뿐이라 지켜지지 않는다.
#   실제로 `cat > TODO.md` 로 완료 이력을 통째로 날린 일이 있었다.
#
# 막는 것
#   1. TODO.md 를 통째로 다시 쓰는 것 (Write · cat > · echo > · Set-Content)
#   2. 프로젝트 폴더 밖 파일을 고치는 것 (allowOutside 에 적은 경로는 통과)
#
# 종료 코드
#   0 통과 / 2 차단 (stderr 가 Claude 에게 전달됨)

INPUT=$(cat)
CONF=".claude/todo-guard.json"

# 설정으로 끌 수 있다
if [ -f "$CONF" ] && grep -q '"preGuard"[[:space:]]*:[[:space:]]*false' "$CONF"; then
  exit 0
fi

TOOL=$(printf '%s' "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

# ── 1. TODO.md 덮어쓰기 ──────────────────────────────────────────
if [ "$TOOL" = "Write" ]; then
  if printf '%s' "$INPUT" | grep -q '"file_path"[[:space:]]*:[[:space:]]*"[^"]*TODO\.md"'; then
    {
      echo "[todo-guard] TODO.md 를 Write 로 통째로 쓰려 했습니다. 차단합니다."
      echo "  이전 항목과 「완료」 이력이 날아갑니다."
      echo "  Edit 도구로 '## 진행 중' 아래에 항목만 덧붙이십시오."
      echo "  파일이 아예 없을 때만 새로 만듭니다."
    } >&2
    exit 2
  fi
fi

if [ "$TOOL" = "Bash" ]; then
  CMD=$(printf '%s' "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)"[[:space:]]*}.*/\1/p')
  # 실제 리다이렉트만 본다. 명령 인자 안에 문자열로 들어간 것은 막지 않는다.
  #   (앞서 시험 명령에 적힌 문자열까지 막아 오탐이 났다)
  if printf '%s' "$CMD" | grep -Eq '(^|[;&|][[:space:]]*)(cat|echo|printf|tee|type)[^;&|]*>[[:space:]]*"?[^"|;&]*TODO\.md|Set-Content[^;&|]*TODO\.md|Out-File[^;&|]*TODO\.md'; then
    if [ -f TODO.md ]; then
      {
        echo "[todo-guard] TODO.md 를 통째로 덮어쓰려 했습니다. 차단합니다."
        echo "  이전 항목과 「완료」 이력이 날아갑니다."
        echo "  항목만 덧붙이십시오:"
        echo "    sed -i '/^## 진행 중/a - [ ] 항목' TODO.md"
        echo "  또는 Edit 도구로 '## 진행 중' 아래에 한 줄 삽입."
      } >&2
      exit 2
    fi
  fi
fi

# ── 2. 프로젝트 밖 편집 ──────────────────────────────────────────
# allowOutside 에 적은 경로는 통과시킨다
if [ "$TOOL" = "Write" ] || [ "$TOOL" = "Edit" ] || [ "$TOOL" = "NotebookEdit" ]; then
  FP=$(printf '%s' "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  [ -z "$FP" ] && exit 0

  # 상대 경로면 프로젝트 안이다
  case "$FP" in
    /*|[A-Za-z]:*|*\\\\*) ;;
    *) exit 0 ;;
  esac

  ROOT=$(pwd -W 2>/dev/null || pwd)
  NORM=$(printf '%s' "$FP" | sed 's|\\\\|/|g')
  ROOTN=$(printf '%s' "$ROOT" | sed 's|\\|/|g')

  case "$NORM" in
    "$ROOTN"*) exit 0 ;;
  esac

  # 시스템이 정해 준 임시·스크래치패드 폴더는 막지 않는다.
  #   중간 산출물을 둘 곳이 막히면 프로젝트 안이 어지러워진다
  case "$NORM" in
    */Temp/claude/*|*/tmp/claude/*|/tmp/*|*/AppData/Local/Temp/*) exit 0 ;;
  esac

  # 허용 목록 확인
  if [ -f "$CONF" ]; then
    ALLOW=$(sed -n 's/.*"allowOutside"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' "$CONF" \
            | tr ',' '\n' | tr -d '" ' | sed 's|\\\\|/|g')
    for a in $ALLOW; do
      [ -z "$a" ] && continue
      case "$NORM" in
        "$a"*) exit 0 ;;
      esac
    done
  fi

  {
    echo "[todo-guard] 프로젝트 폴더 밖 파일을 고치려 했습니다. 차단합니다."
    echo "  고치려는 파일 : $FP"
    echo "  프로젝트 폴더 : $ROOT"
    echo "  사용자에게 확인을 받고, 허가받았으면 아래를 실행한 뒤 다시 시도하십시오."
    echo "    bash ~/.claude/skills/todo-guard/scripts/allow-outside.sh \"$FP\""
    echo "  밖에서 작업하는 동안에는 매 응답 맨 위에 경고 배너를 붙이십시오."
  } >&2
  exit 2
fi

exit 0
