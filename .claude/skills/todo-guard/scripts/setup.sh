#!/usr/bin/env bash
# 「투두가드로 이 프로젝트 세팅해줘」 한 마디로 도는 세팅.
#
# 하는 일
#   1. 전역 ~/.claude/CLAUDE.md 에 「세션 밖 폴더」 규칙이 있는지 보고, 없으면 넣는다
#   2. TODO.md 를 만든다
#   3. 훅 세 개를 프로젝트에 복사한다 (session-start · todo-check · doc-check)
#   4. .claude/settings.json 에 훅을 등록한다
#   5. .claude/todo-guard.json 에 문서 규칙 OFF 를 적는다
#   6. 프로젝트 CLAUDE.md 에 운영 규칙과 문서 규칙 위치를 병합한다
#
# 이미 있는 것은 건드리지 않는다.
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
S="$SKILL/scripts"

say() { echo "  $*"; }

echo "[todo-guard] 세팅 시작 - $(pwd)"

# ── 1. 전역 규칙 ────────────────────────────────────────────────
bash "$S/ensure-global-rule.sh" install

# ── 2. TODO.md ─────────────────────────────────────────────────
if [ -f TODO.md ]; then
  say "TODO.md 이미 있음"
else
  cat > TODO.md <<'MD'
# TODO

## 진행 중

## 완료

## 보류 (사용자 확인 필요)
MD
  say "TODO.md 생성"
fi

# ── 3. 훅 복사 ─────────────────────────────────────────────────
mkdir -p .claude/hooks
# 내용을 복사하지 않고 스킬 본체를 부르는 껍데기만 깐다.
#   복사하면 규칙을 고쳐도 이미 세팅한 프로젝트는 옛 사본으로 돈다.
#   강의자료에서 검사기 사본이 폴더마다 23개씩 생겨 같은 문제를 겪었다.
for f in session-start.sh check-todo.sh doc-check.sh pre-tool.sh; do
  cat > ".claude/hooks/$f" <<SHIM
#!/usr/bin/env bash
# 껍데기. 내용은 ~/.claude/skills/todo-guard/scripts/$f 에 한 벌만 둔다.
exec bash "\$HOME/.claude/skills/todo-guard/scripts/$f" "\$@"
SHIM
done
say "훅 4개 등록 (껍데기) - .claude/hooks/"

# ── 4. settings.json 등록 ──────────────────────────────────────
CONF=".claude/settings.json"
if [ -f "$CONF" ] && grep -q "todo-guard" "$CONF"; then
  say "settings.json 에 이미 등록됨"
else
  if [ -f "$CONF" ]; then
    cp "$CONF" "$CONF.bak-$(date +%Y%m%d-%H%M%S)"
    say "기존 settings.json 은 .bak 으로 남김. hooks 항목을 직접 병합하십시오"
  fi
  cat > "$CONF" <<'JSON'
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "bash .claude/hooks/session-start.sh" } ] }
    ],
    "PreToolUse": [
      { "matcher": "Write|Edit|NotebookEdit|Bash",
        "hooks": [ { "type": "command", "command": "bash .claude/hooks/pre-tool.sh" } ] }
    ],
    "Stop": [
      { "hooks": [
          { "type": "command", "command": "bash .claude/hooks/check-todo.sh" },
          { "type": "command", "command": "bash .claude/hooks/doc-check.sh" }
      ] }
    ]
  }
}
JSON
  say "settings.json 에 훅 등록 (SessionStart 1 · PreToolUse 1 · Stop 2)"
fi

# ── 4-1. 검사에서 뺄 폴더 목록 ─────────────────────────────────
# 남이 쓴 글(강의 소재·인용 자료·받아쓴 원문)까지 문체 검사를 하면
# 고칠 수 없는 위반이 쌓여 턴 종료가 영영 막힌다. 그런 폴더는 여기에 적는다
if [ -f .todoguardignore ]; then
  say ".todoguardignore 이미 있음"
else
  cat > .todoguardignore <<'IGN'
# 문서 검사에서 뺄 폴더·파일 이름을 한 줄에 하나씩 적는다.
# 내가 쓴 글이 아닌 것 - 강의 소재, 인용 자료, 받아쓴 원문 - 을 넣는다.
실습소재
소재
자료
샘플
IGN
  say ".todoguardignore 생성 (실습소재 · 소재 · 자료 · 샘플 제외)"
fi

# ── 5. 문서 규칙 (기본 OFF) ────────────────────────────────────
if [ -f .claude/todo-guard.json ]; then
  say "todo-guard.json 이미 있음 - $(bash "$S/doc-toggle.sh")"
else
  bash "$S/doc-toggle.sh" off >/dev/null
  say "문서 규칙 OFF (.claude/todo-guard.json)"
  say "  슬라이드·보고서를 만드는 프로젝트면 '투두가드 문서 규칙 켜줘' 라고 하십시오"
fi

# ── 6. 프로젝트 CLAUDE.md ──────────────────────────────────────
if [ -f CLAUDE.md ] && grep -q "todo-guard" CLAUDE.md; then
  say "CLAUDE.md 에 이미 병합됨"
else
  [ -f CLAUDE.md ] && printf '\n' >> CLAUDE.md
  cat >> CLAUDE.md <<'MD'
# 작업 관리 규칙 (todo-guard)

## TODO.md 운영

- 사용자의 모든 지시는 즉시 TODO.md 「진행 중」에 `- [ ]` 로 등록한다. 등록 없이 착수 금지
- 항목을 마치면 `- [x]` 로 바꾸고 「완료」로 옮긴다. 실제로 끝나지 않은 것을 완료 처리하지 않는다
- 사용자 판단이 필요해 진행 불가한 항목만 `- [?] 항목명 (사유)` 로 둔다

## 문서 규칙

슬라이드·보고서(`.pptx` `.pdf` `.doc` `.txt` `.hwp` `.md`)를 만들 때는
`~/.claude/skills/todo-guard/rules/doc-rules.md` 를 **쓰기 전에 읽고** 적용한다.

턴을 끝낼 때 바뀐 줄을 자동 검사한다. 위반이 있으면 종료가 막힌다.

| 사용자가 말하면 | 실행 |
|---|---|
| 전체 검수해줘 | `python ~/.claude/skills/todo-guard/scripts/doc-guard.py --all` |
| 바뀐 것만 검수해줘 | `python ~/.claude/skills/todo-guard/scripts/doc-guard.py --changed` |
| 문서 규칙 꺼줘 / 켜줘 | `bash ~/.claude/skills/todo-guard/scripts/doc-toggle.sh off｜on` |
MD
  say "CLAUDE.md 에 운영 규칙 + 문서 규칙 병합"
fi

echo "[todo-guard] 세팅 완료"
echo "  훅은 세션을 열 때 한 번 읽힙니다. /exit 로 나갔다 다시 들어오면 적용됩니다."
