#!/usr/bin/env bash
# SessionStart 훅: stdout 이 Claude 컨텍스트에 주입된다.
#   1) TODO 체계가 없으면 세팅을 지시
#   2) 미완료 항목을 보고
#   3) 문서 규칙 ON/OFF 를 알려 사용자가 켜고 끌 수 있게 한다

TODO_FILE="TODO.md"
CONF=".claude/todo-guard.json"

DOC="ON"
if [ -f "$CONF" ] && grep -q '"docRules"[[:space:]]*:[[:space:]]*false' "$CONF"; then
  DOC="OFF"
fi

if [ ! -f "$TODO_FILE" ]; then
  echo "[todo-guard] 이 프로젝트에 TODO.md 가 없습니다. todo-guard 스킬을 읽고 세팅하십시오 (TODO.md 생성 + 훅 등록 + CLAUDE.md 규칙 병합)."
else
  INCOMPLETE=$(grep -n '^[[:space:]]*- \[ \]' "$TODO_FILE")
  if [ -n "$INCOMPLETE" ]; then
    echo "[todo-guard] 이전 세션의 미완료 작업이 남아 있습니다:"
    echo "$INCOMPLETE"
    echo "사용자에게 보고하고 이어서 처리하십시오."
  else
    echo "[todo-guard] TODO.md 운영 중. 모든 지시는 즉시 '- [ ]' 로 등록, 실제 완료 확인 후에만 '- [x]' 처리."
    echo "  TODO.md 를 통째로 다시 쓰지 말 것. 항목만 덧붙일 것 (덮어쓰면 완료 이력이 날아감)."
  fi
fi

S="$HOME/.claude/skills/todo-guard/scripts"
echo "[todo-guard] 문서 규칙: ${DOC}"
if [ "$DOC" = "ON" ]; then
  echo "  슬라이드·보고서(.pptx .doc .txt .hwp .md) 작업에는 아래 규칙을 적용하십시오."
  echo "  규칙 본문: ~/.claude/skills/todo-guard/rules/doc-rules.md  (문서를 쓰기 전에 읽을 것)"
  echo "  턴을 끝낼 때 바뀐 줄을 자동 검사하고, 위반이 있으면 종료를 막습니다."
else
  echo "  문서 규칙이 꺼져 있습니다. 자동 검사를 하지 않습니다."
fi
echo "[todo-guard] 사용자가 아래처럼 말하면 해당 명령을 실행하십시오."
echo "  \"전체 검수해줘\" / \"투두가드 하네스로 전체 검수\""
echo "      python $S/doc-guard.py --all"
echo "  \"바뀐 것만 검수해줘\""
echo "      python $S/doc-guard.py --changed"
echo "  \"문서 <파일> 검수해줘\""
echo "      python $S/doc-guard.py <파일>"
echo "  \"투두가드 문서 규칙 꺼줘 / 켜줘\""
echo "      bash $S/doc-toggle.sh off   |   bash $S/doc-toggle.sh on"
echo "  \"세션 밖 규칙 확인해줘\""
echo "      bash $S/ensure-global-rule.sh check   (없으면 install)"

exit 0
