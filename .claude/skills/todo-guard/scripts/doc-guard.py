# 문서 하네스 - 슬라이드·보고서 원고를 규칙(rules/doc-rules.md)대로 검사한다.
#
# 왜 필요한가
#   사람 눈으로만 보면 「자리」가 한 문서에 17번 나와도 지나간다.
#   지시대명사·구어·서술 종결은 한 건씩 보면 어색하지 않아 더 잘 새어 나간다.
#
# 무엇을 검사하나 - 바뀐 줄만 본다
#   200장짜리 덱에서 한 장을 고쳤다고 전체를 훑으면 매번 느리고, 이미 넘어간
#   옛 위반이 계속 나와 새 위반이 묻힌다. 그래서 이번에 늘거나 바뀐 줄만 본다.
#
#   .md .txt   git diff 로 추가된 줄 (+)만
#   .pptx      텍스트를 뽑아 직전 검사 때 저장해 둔 것과 대조, 새로 생긴 줄만
#   추적되지 않는 새 파일은 전체가 새 내용이므로 전부 본다
#
# 사용
#   python doc-guard.py --changed     바뀐 줄만 검사 (훅이 쓰는 방식)
#   python doc-guard.py --all         프로젝트의 문서 전체를 검사
#   python doc-guard.py <파일 …>      지정한 파일을 전체 검사
#
# 종료 코드
#   0 위반 없음 / 1 위반 있음
import hashlib
import io
import os
import re
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

DOC_EXT = (".md", ".txt")
PPTX_EXT = (".pptx",)
SKIP_DIR = {".git", "node_modules", "__pycache__", ".venv", "교정", ".claude"}
# 스킬이 만들어 준 파일과 작업 기록은 검사 대상이 아니다.
# 세팅 직후 손대지 않은 파일 때문에 종료가 막히면 쓸 수 없다
SKIP_FILE = {"TODO.md", "CLAUDE.md", "README.md"}
CACHE_DIR = os.path.join(".claude", "todo-guard", "cache")
PASSED = os.path.join(".claude", "todo-guard", "passed.txt")

# ── 규칙 ────────────────────────────────────────────────────────────
# 규칙은 코드에 박아 두지 않는다. rules/harness-rules.md 를 읽는다.
#   사람이 md 표를 고치면 다음 검사부터 바로 적용된다.
#   파이썬을 고쳐야 규칙이 바뀌면, 규칙을 손볼 사람이 손을 못 댄다.
RULE_MD = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "..", "rules", "harness-rules.md")


def _rows(block):
    """코드 블록에서 `이름 = 정규식` 을 뽑는다.

    표를 쓰면 정규식 안의 세로줄이 칸 구분자로 읽혀 규칙이 잘린다.
    그래서 표가 아니라 코드 블록에 적는다.
    """
    out = []
    m = CODE_BLOCK.search(block)
    if not m:
        return out
    for line in m.group(1).split(chr(10)):
        line = line.rstrip()
        if not line.strip():
            continue
        off = line.lstrip().startswith("#")          # # 을 붙이면 그 규칙은 끈다
        if off:
            line = line.lstrip()[1:]
        if "=" not in line:
            continue
        name, _, pat = line.partition("=")
        out.append((off, name.strip(), pat.strip()))
    return out


CODE_BLOCK = re.compile("`{3}" + r"\s*\n(.*?)\n" + "`{3}", re.S)


def load_rules():
    """harness-rules.md 를 읽어 규칙을 만든다. 잘못된 정규식은 건너뛰고 알린다."""
    ban, cliche, limit, body, head = ["자리"], [], 8, [], []
    try:
        md = io.open(RULE_MD, encoding="utf-8").read()
    except OSError:
        print("  규칙 파일을 못 읽음: %s" % RULE_MD)
        return ban, cliche, limit, body, head

    def sec(title):
        i = md.find("## " + title)
        if i < 0:
            return ""
        j = md.find(chr(10) + "## ", i + 1)
        return md[i:j if j > 0 else len(md)]

    m = CODE_BLOCK.search(sec("1. 금지어"))
    if m:
        ban = [w.strip() for w in re.split(r"[,\s]+", m.group(1)) if w.strip()]

    m = CODE_BLOCK.search(sec("2. 상투어"))
    if m:
        txt = m.group(1)
        lm = re.search(r"한도\s*:\s*(\d+)", txt)
        if lm:
            limit = int(lm.group(1))
            txt = txt[lm.end():]
        cliche = [w.strip() for w in txt.split() if w.strip()]

    for title, bucket in (("3. 본문 규칙", body), ("4. 제목 규칙", head)):
        for off, name, pat in _rows(sec(title)):
            if off:
                continue
            try:
                bucket.append((name, re.compile(pat)))
            except re.error as exc:
                print("  규칙 건너뜀 - %s : %s" % (name, exc))
    return ban, cliche, limit, body, head


BAN, CLICHE, LIMIT, RULES, HEAD_RULES = load_rules()

# 「안 · 못 + 명사형」 은 구어다. 「안 엉킴」 「안 깨짐」 「못 함」.
# 끝 글자의 받침이 ㅁ 인지로 본다. 낱말을 나열하면 「엉킴」 같은 것이 새어 나간다
NEG_NOUN = re.compile(r"(?<![가-힣])(안|못)\s+([가-힣]+)(?![가-힣])")


# 「바뀐다」 「간다」 처럼 받침 ㄴ 뒤에 「다」 가 오면 평서형이다.
# 낱말을 나열하면(한다·본다·간다…) 활용형이 끝없이 새어 나간다
PLAIN_ND = re.compile(r"([가-힣])다\s*[.]?\s*$")


def is_plain_end(t):
    m = PLAIN_ND.search(t)
    if not m:
        return False
    ch = ord(m.group(1))
    if not (0xAC00 <= ch <= 0xD7A3):
        return False
    return (ch - 0xAC00) % 28 == 4          # 받침 ㄴ


# 약어는 첫 등장 때 풀네임을 함께 적는다.
#   한 줄만 보면 판정할 수 없다. 문서 전체에서 처음 나온 자리를 찾아야 한다.
ABBR = re.compile(r"(?<![A-Za-z0-9])([A-Z]{2,6})(?![A-Za-z0-9])")
# 풀네임을 적을 필요가 없는 것 - 제품·기술 이름이거나 이미 굳은 말
ABBR_OK = {
    # 이미 굳은 말·단위·형식
    "AI", "PC", "OS", "TV", "USB", "PDF", "PPT", "URL", "URI", "HTML", "CSS",
    "JS", "JSON", "YAML", "XML", "HTTP", "HTTPS", "CLI", "GUI", "IDE", "API",
    "MB", "GB", "KB", "TB", "OK", "ID", "PW", "QR", "IT", "DB",
    "CPU", "GPU", "RAM", "SSD", "HDD", "USD", "KRW", "FAQ", "TODO",
    "README", "MD", "TXT", "CSV", "WAV", "MP3", "MP4", "PNG", "JPG",
    "NAS", "VPN", "DNS", "IP", "UTC", "KST", "AM", "PM", "SSH", "PATH",
    "LTS", "CMD", "MCP", "LLM", "RAG", "GPT", "MVP", "UI", "UX", "PRD",
    "SDD", "UML", "POSIX", "CI", "CD", "DLC", "AWS", "SDK", "REST", "RTT",
    # 제품·회사·파일 이름
    "CLAUDE", "VS", "MS", "GIT", "LM", "PS", "IPTV", "KT", "HUD", "KOSTA",
    # 화면에 그대로 찍히는 낱말
    "WHY", "WHAT", "HOW", "OFF", "ON", "GET", "POST", "PUT", "DELETE",
    "TCP", "UDP",
}
# 「CLI (Command Line Interface)」 처럼 괄호 안에 풀네임이 오면 병기로 본다
ABBR_PAIR = r"\(\s*[A-Za-z][A-Za-z /\-]{4,}\s*\)"


def check_abbr(lines):
    """약어가 첫 등장에서 풀네임 없이 쓰였는지 본다."""
    seen, hits = set(), []
    for no, t in lines:
        if SKIP_LINE.match(t):
            continue
        for m in ABBR.finditer(t):
            ab = m.group(1)
            if ab in ABBR_OK or ab in seen:
                continue
            seen.add(ab)
            tail = t[m.end():m.end() + 60]
            if re.match(r"\s*" + ABBR_PAIR, tail):
                continue                      # 풀네임 병기됨
            hits.append((no, "약어 첫 등장", "%s - 풀네임 병기 없음 : %s" % (ab, t[:50])))
    return hits


def has_m_final(word):
    if not word:
        return False
    ch = ord(word[-1])
    if not (0xAC00 <= ch <= 0xD7A3):
        return False
    return (ch - 0xAC00) % 28 == 16        # 받침 ㅁ


# HEAD_RULES 는 harness-rules.md 4절에서 읽는다

SKIP_LINE = re.compile(
    r"^\s*(PS\s|>\s|\$\s|#\s|\||```|!\[|\[터미널\]|\[대사\]|INFO:|GET\s|POST\s|PUT\s|DELETE\s)")
LITERAL_OK = ["경로를 찾을 수 없습니다", "액세스가 거부되었습니다",
              "스크립트를 실행할 수 없으므로", "찾을 수 없습니다", "실행할 수 없습니다"]


# ── 읽기 ────────────────────────────────────────────────────────────
def git(*args):
    try:
        # git 은 한글 파일명을 ì´ 처럼 8진수로 감싸 내보낸다.
        # quotepath=false 로 꺼야 파일을 찾을 수 있다
        r = subprocess.run(("git", "-c", "core.quotepath=false") + args,
                           capture_output=True, text=True,
                           encoding="utf-8", errors="replace")
        return r.stdout if r.returncode == 0 else ""
    except Exception:
        return ""


def in_git():
    return git("rev-parse", "--is-inside-work-tree").strip() == "true"


MONO_FONT = re.compile(
    r"cascadia|consol|courier|monaco|menlo|d2coding|나눔고딕코딩|굴림체|dotum|monospace",
    re.I)


def _dark(shape):
    """창 배경처럼 어두운 도형인지. 터미널·코드 창을 가려내는 데 쓴다."""
    try:
        fill = shape.fill
        if fill.type is None or fill.type != 1:
            return False
        rgb = str(fill.fore_color.rgb)
        r, g, b = int(rgb[0:2], 16), int(rgb[2:4], 16), int(rgb[4:6], 16)
        return (0.299 * r + 0.587 * g + 0.114 * b) < 90
    except Exception:
        return False


def _center(sh):
    if sh.left is None or sh.top is None:
        return None
    return (sh.left + (sh.width or 0) // 2, sh.top + (sh.height or 0) // 2)


def pptx_lines(path):
    """pptx 에서 (슬라이드 번호, 텍스트)를 뽑는다. python-pptx 가 없으면 None.

    화면에 그대로 찍히는 것은 문체 규칙 대상이 아니다. 아래를 걸러낸다.
      - 어두운 창(터미널·코드) 안에 놓인 글
      - 고정폭 글꼴로 찍은 글 (명령·경로·코드)
      - 한글이 없는 줄 (영문 화면 문구)
    """
    try:
        from pptx import Presentation
    except ImportError:
        return None
    HAN = re.compile(r"[가-힣]")
    out = []
    for i, slide in enumerate(Presentation(path).slides, 1):
        # 어두운 창의 좌표 범위를 먼저 모은다
        zones = []
        for sh in slide.shapes:
            if _dark(sh) and sh.width and sh.height:
                zones.append((sh.left, sh.top, sh.left + sh.width, sh.top + sh.height))

        def in_dark(sh):
            c = _center(sh)
            if not c:
                return False
            return any(x1 <= c[0] <= x2 and y1 <= c[1] <= y2 for x1, y1, x2, y2 in zones)

        for sh in slide.shapes:
            if sh.has_text_frame:
                if in_dark(sh):
                    continue
                for para in sh.text_frame.paragraphs:
                    runs = list(para.runs)
                    t = "".join(r.text for r in runs).strip()
                    if not t or not HAN.search(t):
                        continue
                    # 글꼴 이름이 하나도 없으면(테마 상속) 고정폭이라고 볼 수 없다.
                    #   all([]) 이 True 라서, 이름 없는 글이 전부 코드로 판정돼
                    #   손으로 만든 pptx 본문이 통째로 검사에서 빠졌다
                    named = [nm for nm in (r.font.name for r in runs) if nm]
                    if named and all(MONO_FONT.search(nm) for nm in named):
                        continue          # 고정폭 = 명령·코드
                    out.append((i, t))
            if getattr(sh, "has_table", False):
                for row in sh.table.rows:
                    for cell in row.cells:
                        t = cell.text.strip()
                        if t and HAN.search(t):
                            out.append((i, t))
    return out


def text_lines(path):
    raw = io.open(path, encoding="utf-8", errors="replace").read()
    return [(i, l.strip()) for i, l in enumerate(raw.split("\n"), 1) if l.strip()]


def cache_path(path):
    key = hashlib.md5(os.path.abspath(path).encode("utf-8")).hexdigest()[:16]
    return os.path.join(CACHE_DIR, key + ".txt")


def added_text_lines(path):
    """추적 중인 텍스트 문서에서 이번에 추가된 줄만 돌려준다."""
    diff = git("diff", "-U0", "HEAD", "--", path)
    if not diff:
        diff = git("diff", "-U0", "--", path)
    if not diff:
        return []
    out, no = [], 0
    for l in diff.split("\n"):
        m = re.match(r"^@@ -\d+(?:,\d+)? \+(\d+)", l)
        if m:
            no = int(m.group(1))
            continue
        if l.startswith("+") and not l.startswith("+++"):
            t = l[1:].strip()
            if t:
                out.append((no, t))
            no += 1
    return out


def new_pptx_lines(path):
    """직전 검사 때 저장해 둔 텍스트와 대조해 새로 생긴 줄만 돌려준다."""
    cur = pptx_lines(path)
    if cur is None:
        return None, None
    cp = cache_path(path)
    old = set()
    if os.path.exists(cp):
        old = set(io.open(cp, encoding="utf-8").read().split("\n"))
    fresh = [(no, t) for no, t in cur if t not in old]
    return fresh, cur


def save_cache(path, lines):
    os.makedirs(CACHE_DIR, exist_ok=True)
    io.open(cache_path(path), "w", encoding="utf-8", newline="\n").write(
        "\n".join(t for _, t in lines))


# ── 검사 ────────────────────────────────────────────────────────────
def scan(lines, label, path):
    hits, counts = [], {}
    for no, t in lines:
        if SKIP_LINE.match(t) or any(k in t for k in LITERAL_OK):
            continue
        for w in BAN:
            if w in t:
                hits.append((no, "금지어 " + w, t))
        neg = NEG_NOUN.search(t)
        if neg and has_m_final(neg.group(2)):
            hits.append((no, "안-명사형", t))
        if is_plain_end(t):
            hits.append((no, "평서형 종결", t))
        # 한 줄에 위반이 여럿일 수 있다. break 로 끊으면 나머지가 숨는다
        seen = set()
        for name, rx in RULES:
            if rx.search(t):
                hits.append((no, name, t))
                seen.add(name)
        # 제목 규칙은 제목에만 건다.
        #   md 는 # 로 시작하는 줄, 그 밖에는 조사·불릿이 없는 짧은 줄
        is_md_head = t.startswith("#")
        head = re.sub(r"^#+\s*", "", t)
        looks_head = (is_md_head or
                      (len(head) <= 24 and not head.startswith("- ")
                       and not re.search(r"[.,·:;]", head)))
        if looks_head:
            for name, rx in HEAD_RULES:
                if rx.search(head):
                    # 본문 규칙에서 이미 잡은 것과 겹치면 두 번 세지 않는다
                    if name == "제목 서술 종결" and "평서형 종결" in seen:
                        continue
                    hits.append((no, name, head))
        for w in re.findall(r"[가-힣]{2,}", t):
            if w in CLICHE:
                counts[w] = counts.get(w, 0) + 1

    # 약어는 문서 전체를 훑어야 첫 등장을 알 수 있다.
    #   바뀐 줄만 볼 때는 첫 등장인지 알 수 없으므로 전수일 때만 본다
    if label == "전체":
        hits += check_abbr(lines)

    over = [(w, c) for w, c in sorted(counts.items(), key=lambda x: -x[1]) if c >= LIMIT]
    print("%s : %s %d줄 - 위반 %d건 / 상투어 반복 %d개"
          % (path, label, len(lines), len(hits), len(over)))
    for no, name, t in hits[:40]:
        print("  [%s] %-12s %s" % (no, name, t[:70]))
    if len(hits) > 40:
        print("  … 그 밖 %d건" % (len(hits) - 40))
    for w, c in over:
        print("  상투어  %-6s %d회" % (w, c))
    return len(hits) + len(over)


def passed_set():
    if not os.path.exists(PASSED):
        return set()
    return {l.strip() for l in io.open(PASSED, encoding="utf-8") if l.strip()}


def mark_passed(path):
    os.makedirs(os.path.dirname(PASSED), exist_ok=True)
    done = passed_set()
    done.add(os.path.normpath(path))
    NL = chr(10)
    io.open(PASSED, "w", encoding="utf-8", newline=NL).write(NL.join(sorted(done)))


def fresh_lines(path, reader):
    """직전 검사 때 저장해 둔 것과 대조해 새로 생긴 줄만 돌려준다.

    git 을 쓰지 않는다. 저장소가 아닌 폴더에서도 똑같이 돌아야 한다.
    """
    cur = reader(path)
    if cur is None:
        return None, None
    cp = cache_path(path)
    old = set()
    if os.path.exists(cp):
        old = set(io.open(cp, encoding="utf-8").read().split(chr(10)))
    return [(no, t) for no, t in cur if t not in old], cur


def check_changed(path, tracked=False):
    # 한 번도 하네스를 통과한 적이 없는 문서는 처음 한 번 전수한다.
    #   바뀐 줄만 보면, 예전부터 있던 위반은 영영 검사받지 않는다
    if os.path.normpath(path) not in passed_set():
        print("%s : 투두가드 문서 하네스를 한 번도 통과하지 않음 - 전수 검사합니다" % path)
        n = check_all(path)
        if n == 0:
            mark_passed(path)
            print("  전수 통과. 다음부터는 바뀐 줄만 검사합니다")
        return n

    ext = os.path.splitext(path)[1].lower()
    reader = pptx_lines if ext in PPTX_EXT else (text_lines if ext in DOC_EXT else None)
    if reader is None:
        return 0

    fresh, cur = fresh_lines(path, reader)
    if fresh is None:
        print("  건너뜀 %s  (python-pptx 없음: pip install python-pptx)" % path)
        return 0
    save_cache(path, cur)
    if not fresh:
        print("%s : 바뀐 줄 없음" % path)
        return 0
    return scan(fresh, "바뀐 줄", path)


def check_all(path):
    ext = os.path.splitext(path)[1].lower()
    if ext in PPTX_EXT:
        lines = pptx_lines(path)
        if lines is None:
            print("  건너뜀 %s  (python-pptx 없음)" % path)
            return 0
        save_cache(path, lines)
    elif ext in DOC_EXT:
        lines = text_lines(path)
        # 전수 검사한 내용이 다음 증분 검사의 기준이 된다.
        # 저장하지 않으면 기준이 비어 있어 다음번에 파일 전체가 「바뀐 줄」로 잡힌다
        save_cache(path, lines)
    else:
        return 0
    return scan(lines, "전체", path)


def ignore_list():
    """프로젝트 루트의 .todoguardignore 에 적힌 폴더·파일을 검사에서 뺀다.

    검사 기록이나 참고 자료를 폴더에 두면 그것까지 검사해 결과가 뒤섞인다.
    """
    out = set()
    if os.path.exists(".todoguardignore"):
        for line in io.open(".todoguardignore", encoding="utf-8"):
            line = line.strip()
            if line and not line.startswith("#"):
                out.add(line.rstrip("/").rstrip(chr(92)))
    return out


def walk_docs():
    skip = SKIP_DIR | ignore_list()
    found = []
    for root, dirs, names in os.walk("."):
        dirs[:] = [d for d in dirs if d not in skip]
        for nm in names:
            if nm in SKIP_FILE or nm in skip:
                continue
            if nm.lower().endswith(DOC_EXT + PPTX_EXT):
                found.append(os.path.join(root, nm))
    return found


def print_rules():
    print("# 하네스가 잡는 것  (doc-guard.py --rules 로 뽑음)")
    print()
    print("| # | 이름 | 정규식 |")
    print("|---|---|---|")
    i = 1
    print("| %d | %s | %s |" % (i, "금지어", " · ".join(BAN))); i += 1
    print("| %d | %s | %s |" % (i, "안-명사형", "안·못 + ㅁ받침 명사형")); i += 1
    for name, rx in RULES:
        print("| %d | %s | `%s` |" % (i, name, rx.pattern.replace(chr(124), chr(92)+chr(124))[:90]))
        i += 1
    for name, rx in HEAD_RULES:
        print("| %d | %s | `%s` |" % (i, name, rx.pattern.replace(chr(124), chr(92)+chr(124))[:90]))
        i += 1
    print("| %d | %s | %d회 초과: %s |" % (i, "상투어 반복", LIMIT, " ".join(CLICHE)))
    print()
    print("검사 대상: %s  %s" % (" ".join(DOC_EXT), " ".join(PPTX_EXT)))
    print("검사 제외 파일: %s" % " ".join(sorted(SKIP_FILE)))


def main():
    args = sys.argv[1:]
    if args and args[0] == "--rules":
        print_rules()
        return 0

    if args and args[0] == "--changed":
        # git 을 쓰지 않는다. 저장소든 아니든 똑같이 돌아야 한다.
        #   폴더의 문서를 모아, 직전 검사분과 대조해 바뀐 줄만 본다
        files = [(f, False) for f in walk_docs()]
        def keep(f):
            if not os.path.exists(f):
                return False
            if os.path.basename(f) in SKIP_FILE:
                return False
            # git 이 내놓은 경로도 제외 폴더를 거치게 한다.
            # 안 그러면 .claude/todo-guard/passed.txt 같은 자기 산출물을 검사한다
            parts = os.path.normpath(f).replace(chr(92), "/").split("/")
            if any(d in SKIP_DIR for d in parts):
                return False
            return f.lower().endswith(DOC_EXT + PPTX_EXT)

        files = [(f, t) for f, t in files if keep(f)]
        if not files:
            print("바뀐 문서 없음.")
            print("합계 0건")
            return 0
        total = sum(check_changed(f, t) for f, t in files)
    else:
        files = walk_docs() if (not args or args[0] == "--all") else args
        if not files:
            print("검사할 문서 없음.")
            return 0
        total = 0
        for f in files:
            n = check_all(f)
            if n == 0:
                mark_passed(f)
            total += n

    print()
    print("=" * 66)
    print("합계 %d건  (문서 %d개)" % (total, len(files)))
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
