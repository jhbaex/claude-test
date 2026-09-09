#!/usr/bin/env bash
# Stop 훅: 문서 규칙이 ON 이면 바뀐 문서를 검사하고, 위반이 있으면 턴 종료를 막는다.
# exit 0 = 종료 허용 / exit 2 = 차단 (stderr 가 Claude 에게 전달됨)
INPUT=$(cat)
echo "$INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && exit 0

CONF=".claude/todo-guard.json"
[ -f "$CONF" ] && grep -q '"docRules"[[:space:]]*:[[:space:]]*false' "$CONF" && exit 0

SKILL="$HOME/.claude/skills/todo-guard/scripts/doc-guard.py"
[ -f "$SKILL" ] || exit 0

# git 을 쓰지 않는다. 저장소든 아니든 똑같이 돈다.
#   전에는 여기서 git 저장소가 아니면 빠져나갔다. 그래서 저장소가 아닌 폴더는
#   아무 검사도 받지 않고 통과했다. doc-guard.py 가 직전 검사분과 대조해
#   바뀐 줄을 가리므로 git 이 필요 없다.
OUT=$(PYTHONIOENCODING=utf-8 python "$SKILL" --changed 2>&1)
echo "$OUT" | grep -q "^합계 0건" && exit 0
echo "$OUT" | grep -q "검사할 문서 없음" && exit 0

{
  echo "[todo-guard 문서 규칙] 문서 규칙 위반이 남아 있습니다. 아래를 고친 뒤 끝내십시오."
  echo "규칙: ~/.claude/skills/todo-guard/rules/doc-rules.md"
  echo "$OUT"
  echo "규칙을 적용하지 않으려면 사용자에게 '투두가드 문서 규칙 꺼줘' 를 요청하십시오."
  echo "내가 쓴 글이 아니라 고칠 수 없는 파일(강의 소재·인용 자료·받아쓴 원문)이면 그 폴더 이름을 .todoguardignore 에 한 줄 넣으십시오."
} >&2
exit 2
