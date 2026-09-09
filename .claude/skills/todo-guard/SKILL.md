---
name: todo-guard
description: 별칭 "투두가드" — 사용자가 이 별칭으로 부르면 이 스킬(todo-guard)을 뜻한다. 두 가지를 한다. (1) TODO.md 기반 작업 추적과 Stop hook 검증을 세팅해 지시를 드랍하지 않게 만든다. (2) 슬라이드·보고서 등 문서(.pptx .doc .txt .hwp .md)에 문서 작성 규칙과 문체 하네스를 적용한다(기본 OFF, 문서 프로젝트에서만 켬). 다음 상황에서 사용할 것 - 사용자가 "todo-guard"·"투두가드"를 지목해 세팅을 요청할 때, 작업 누락 방지 체계 구축을 요청할 때, 문서 검수·문체 규칙·"전체 검수해줘"·"바뀐 것만 검수해줘"를 요청할 때, "문서 규칙 꺼줘/켜줘"라고 할 때. 또한 .claude/hooks/doc-check.sh 나 TODO.md 가 있는 프로젝트에서 문서를 만들거나 고칠 때는 rules/doc-rules.md 를 먼저 읽고 이 스킬의 운영 규칙을 따를 것.
---

# TODO Enforcer

TODO.md를 단일 진실 소스로 사용하고, Stop hook이 턴 종료 시 미완료 항목(`- [ ]`)을 검사해 종료를 차단하는 작업 누락 방지 체계.

이 스킬은 `~/.claude/skills/todo-guard/`에 전역 설치되어 있고, 번들 스크립트는 `~/.claude/skills/todo-guard/scripts/`에 있다.

상황 판단:

| 상황 | 수행할 섹션 |
|---|---|
| 사용자가 todo-guard를 지목해 이 프로젝트/세션에 세팅 요청 | A. 프로젝트 로컬 세팅 |
| TODO.md + .claude/hooks/todo-check.sh가 이미 있는 프로젝트에서 작업 중 | B. 운영 규칙 준수 |
| 사용자가 "전역으로 걸어줘" / 모든 프로젝트 자동 적용 요청 | C. 전역 hook 설치 |
| 슬라이드·보고서 등 문서를 만들거나 고칠 때 | A-2. 문서 규칙 |

---

## A. 프로젝트 로컬 세팅

「투두가드로 이 프로젝트 세팅해줘」를 받으면 **아래 한 줄을 실행한다.**
단계를 손으로 따라 하지 않는다. 빠뜨리는 항목이 생긴다.

```bash
bash ~/.claude/skills/todo-guard/scripts/setup.sh
```

### setup.sh 가 하는 일

| # | 하는 일 | 결과 |
|---|---|---|
| 1 | 전역 `~/.claude/CLAUDE.md` 에 「세션 밖 폴더」 규칙 확인 | 없으면 넣음 (있으면 안 건드림) |
| 2 | `TODO.md` 생성 | 진행 중 / 완료 / 보류 |
| 3 | 훅 3개 등록 | `.claude/hooks/` 에 **껍데기** 3줄씩 |
| 4 | `.claude/settings.json` 에 훅 등록 | SessionStart 1개 · Stop 2개 |
| 5 | 문서 규칙 ON | `.claude/todo-guard.json` |
| 6 | 프로젝트 `CLAUDE.md` 에 규칙 병합 | 운영 규칙 + 문서 규칙 위치 |

이미 있는 것은 건드리지 않는다.

### 훅을 복사하지 않고 껍데기로 두는 이유

프로젝트에 놓이는 훅은 스킬 본체를 부르는 3줄짜리다.

```bash
exec bash "$HOME/.claude/skills/todo-guard/scripts/session-start.sh" "$@"
```

내용을 복사하면 규칙을 고쳐도 **이미 세팅한 프로젝트는 옛 사본으로 돈다.**
실제로 강의자료에서 검사기 사본이 폴더마다 23개씩 생겨, 한 곳을 고쳐도
나머지가 옛 규칙으로 통과하는 일을 겪었다.

### 세팅 완료 보고

1. `setup.sh` 출력을 그대로 보여준다
2. **훅은 세션을 열 때 한 번 읽힌다.** `/exit` 로 나갔다 다시 들어와야 적용된다고 알린다
3. 문서 규칙이 ON 이라는 것과 끄는 방법을 알린다

---

## A-2. 문서 규칙 (기본 OFF)

슬라이드·보고서(`.pptx` `.doc` `.txt` `.hwp` `.md`)를 만들 때 적용한다.

### 흐름

```
①  rules/doc-rules.md 를 읽는다      ← 문서를 쓰기 전. 반드시
②  문서를 쓴다
③  Stop 훅이 doc-guard.py 로 검사   ← 쓴 뒤. 자동
    한 번도 통과 안 한 문서는 전수, 통과한 문서는 바뀐 줄만
④  위반이 있으면 종료가 막힌다 → 고치고 ①로
```

### 규칙과 하네스

| | 규칙 | 하네스 |
|---|---|---|
| 파일 | `rules/doc-rules.md` | `scripts/doc-guard.py` |
| 언제 | 쓰기 **전** | 쓴 **뒤** |
| 무엇 | 어떻게 쓸지 가이드 | 잘못 쓴 것 잡아내기 |
| 고치면 | 즉시 적용 (제가 읽음) | `rules/harness-rules.md` 를 고침 |

**검사 규칙은 `rules/harness-rules.md` 에 있다.** 검사기가 그 파일을 읽는다.
사람이 목록을 고치면 다음 검사부터 바로 적용된다. 파이썬을 고칠 필요가 없다.

### 사용자가 말하면 실행할 것

| 사용자 말 | 실행 |
|---|---|
| 전체 검수해줘 | `python ~/.claude/skills/todo-guard/scripts/doc-guard.py --all` |
| 바뀐 것만 검수해줘 | `python ~/.claude/skills/todo-guard/scripts/doc-guard.py --changed` |
| 문서 규칙 꺼줘 / 켜줘 | `bash ~/.claude/skills/todo-guard/scripts/doc-toggle.sh off｜on` |
| 검사 규칙 보여줘 | `python ~/.claude/skills/todo-guard/scripts/doc-guard.py --rules` |

### 검사에서 뺄 폴더 - `.todoguardignore`

프로젝트 루트의 `.todoguardignore` 에 적은 폴더·파일은 문서 검사에서 빠진다.
한 줄에 하나, `#` 로 시작하는 줄은 주석이다. `setup.sh` 가 기본값으로 만들어 둔다.

```
실습소재
소재
자료
샘플
```

**넣어야 하는 것** - 내가 쓴 글이 아닌 것. 강의 소재, 인용한 남의 문서,
받아쓴 원문, 회의 대본처럼 사람 발화를 옮긴 파일.

이런 파일은 개조식으로 고칠 수가 없다. 고치면 원본이 아니게 된다.
그런데도 검사 대상에 남겨 두면 위반이 계속 나와 **턴 종료가 영영 막힌다.**
실제로 회의 대본 16줄 때문에 위반 16건이 나와 작업이 멈춘 적이 있다.

**넣지 말아야 하는 것** - 내가 쓴 문서. 검사를 피하려고 넣는 것은 규칙을 끄는 것과 같다.
전부 끄려면 사용자에게 「투두가드 문서 규칙 꺼줘」 를 요청한다.

### 검사 상태 파일

`.claude/todo-guard/` 아래 두 개를 스킬이 관리한다. 사람이 손댈 일은 없다.

- `passed.txt` — 전수 검사를 통과한 문서 목록
- `cache/` — 「바뀐 줄」을 가리는 기준

---

## B. 운영 규칙 (세팅된 프로젝트에서 상시)

1. **지시 수신 즉시 등록**: 사용자 지시를 받으면 다른 일을 하기 전에 TODO.md "진행 중"에 `- [ ]` 항목으로 추가한다.

   **TODO.md 를 통째로 다시 쓰지 않는다.** 항목만 덧붙인다.
   `cat > TODO.md` 나 Write 로 파일 전체를 쓰면 이전 항목과 「완료」 이력이 날아간다.

   | 쓰지 않는다 | 이렇게 한다 |
   |---|---|
   | `cat > TODO.md <<EOF …` | Edit 도구로 "## 진행 중" 아래에 한 줄 삽입 |
   | Write 로 파일 전체 작성 | `sed -i '/^## 진행 중/a - [ ] 항목' TODO.md` |

   파일이 아예 없을 때만 새로 만든다.
2. **작업 단위 분해**: 항목 하나 = 검증 가능한 산출물 하나. "인라인 창 통합"(X) → "인라인 창 목록화", "1~3번 이관", "4~6번 이관"(O).
3. **거짓 완료 금지**: 실제 파일 반영·테스트 통과·결과물 출력이 확인된 경우에만 `- [x]` 처리한다.
4. **진행 불가 시 `- [?]`**: 사용자 판단이 필요하면 `- [?] 항목명 (사유)`로 바꾸고 사용자에게 질문한다. Stop hook 차단을 피하려고 `- [?]`를 남용하지 않는다.
5. **세션 시작 시 미완료 보고**: SessionStart hook이 미완료 항목을 알려주면 사용자에게 보고 후 이어서 처리한다.
6. **compaction 전**: 현재 미완료 작업을 전부 TODO.md에 반영한 뒤 compact한다.

---

## C. 전역 hook 설치 (선택)

사용자가 프로젝트마다 세팅하기 싫고 모든 프로젝트에 자동 적용을 원할 때만 수행한다. A-3/A-4와 동일하되 경로만 전역으로:

```bash
mkdir -p ~/.claude/hooks
cp ~/.claude/skills/todo-guard/scripts/check-todo.sh ~/.claude/hooks/todo-check.sh
cp ~/.claude/skills/todo-guard/scripts/session-start.sh ~/.claude/hooks/todo-session-start.sh
chmod +x ~/.claude/hooks/todo-check.sh ~/.claude/hooks/todo-session-start.sh
```

`~/.claude/settings.json`에 A-4와 같은 형식으로 병합하되 command 경로를 `bash ~/.claude/hooks/...`로 지정한다. 스크립트는 TODO.md 없는 프로젝트에서 exit 0으로 통과하므로 전역 등록이 안전하다. 전역 등록 시 SessionStart hook이 TODO.md 없는 프로젝트에서 "세팅하라"는 메시지를 주입하므로, 새 프로젝트도 세션만 열면 자동 세팅된다.

---

## 거짓 완료 감지 강화 (선택)

사용자가 특정 작업의 실제 검증을 요청하면 .claude/hooks/todo-check.sh에 grep/테스트 기반 판정 블록을 추가해준다. 예:

```bash
# 예: 인라인 렌더링 코드가 남아 있으면 "통합 완료" 항목을 거짓 완료로 판정
if grep -q '\[x\].*인라인 창 통합' "$TODO_FILE"; then
  if grep -rq 'renderInline' src/; then
    echo "TODO에는 완료로 표시됐지만 src/에 renderInline 호출이 남아 있습니다. 실제로 통합을 완료하십시오." >&2
    exit 2
  fi
fi
```

---

## 윈도우 환경 참고

- 스크립트 실행은 Git Bash 기반이다 (Claude Code 윈도우 버전의 요구사항이므로 별도 설치 불필요). settings.json의 `bash .claude/hooks/...` command는 윈도우에서도 그대로 동작한다.
- `chmod +x`는 윈도우에서 불필요하다. 실패해도 무시하고 진행한다.
- 세팅 시 파일 복사는 bash의 `cp`와 `~` 확장을 그대로 사용한다 (Git Bash가 `~`를 `%USERPROFILE%`로 해석).
- 스크립트 파일이 CRLF로 변환되면 bash 실행이 깨질 수 있다. 복사 후 실행 오류가 나면 `sed -i 's/\r$//' .claude/hooks/*.sh`로 LF 변환한다.

## 한계

- Stop hook은 턴 종료 시점에만 개입한다. 턴 중간의 건너뛰기 자체를 막지는 못하고, 건너뛴 채 끝내는 것을 잡는다.
- TODO.md 등록 자체를 누락하면 hook도 못 잡는다 → CLAUDE.md 규칙과 병행하는 이유.
- grep으로 검증 불가능한 작업(판단·설계)은 자기 신고에 의존한다. 중요 작업은 실제 검증 블록을 추가할 것.
