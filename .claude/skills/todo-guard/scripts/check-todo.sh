#!/usr/bin/env bash
# TODO.md에 미완료 항목(- [ ])이 있으면 Claude의 턴 종료를 차단한다.
# exit 0 = 종료 허용 / exit 2 = 종료 차단 (stderr가 Claude에게 전달됨)

# stdin으로 들어오는 hook 입력(JSON)에서 stop_hook_active 확인
# → 무한 루프 방지: 이미 hook에 의해 재개된 턴이면 통과시킨다.
INPUT=$(cat)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | grep -o '"stop_hook_active"[[:space:]]*:[[:space:]]*true')

if [ -n "$STOP_HOOK_ACTIVE" ]; then
  # 이미 한 번 차단되어 재개된 턴 → 두 번째부터는 통과 (루프 방지)
  exit 0
fi

TODO_FILE="TODO.md"

# TODO.md가 없으면 통과
if [ ! -f "$TODO_FILE" ]; then
  exit 0
fi

# 미완료 항목 추출 (- [ ] 만, - [?] 는 제외)
INCOMPLETE=$(grep -n '^[[:space:]]*- \[ \]' "$TODO_FILE")

# TODO.md 가 비어 있으면 등록을 아예 안 한 것이다.
#   「적어 둔 걸 지웠는지」가 아니라 「받은 지시를 적었는지」를 봐야 한다
# grep -c 는 0 을 찍고도 실패 코드를 낸다. || echo 0 을 붙이면 "0\n0" 이 되어
# 비교가 어긋난다. 출력만 쓰고 종료 코드는 무시한다
ITEMS=$(grep -c '^[[:space:]]*- \[' "$TODO_FILE" 2>/dev/null)
ITEMS=${ITEMS:-0}
if [ "$ITEMS" = "0" ]; then
  echo "TODO.md 에 항목이 하나도 없습니다. 이번 턴에 받은 지시를 등록하지 않았는지 확인하십시오." >&2
  echo "  지시를 받았다면 '## 진행 중' 아래에 '- [ ] 항목' 을 덧붙이고, 끝냈으면 '- [x]' 로 바꿔 '## 완료' 로 옮기십시오." >&2
  echo "  등록할 지시가 없었다면 TODO.md 에 '- [x] (해당 없음)' 한 줄을 남기십시오." >&2
  exit 2
fi

if [ -n "$INCOMPLETE" ]; then
  echo "TODO.md에 미완료 작업이 남아 있습니다. 아래 항목을 지금 처리하거나, 진행 불가 사유가 있으면 해당 항목을 '- [?] 항목명 (사유)'로 바꾸십시오:" >&2
  echo "$INCOMPLETE" >&2
  exit 2
fi

exit 0
