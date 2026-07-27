# claude-statusline

[![GitHub Release](https://img.shields.io/github/v/release/ahngbeom/claude-statusline)](https://github.com/Ahngbeom/claude-statusline/releases)
[![CI](https://github.com/ahngbeom/claude-statusline/actions/workflows/ci.yml/badge.svg)](https://github.com/ahngbeom/claude-statusline/actions/workflows/ci.yml)

A detailed, informative statusline for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI.

Claude Code CLI를 위한 상세한 상태 표시줄입니다.

---

## Features / 기능

Display comprehensive session information in your Claude Code terminal:

Claude Code 터미널에 다양한 세션 정보를 표시합니다:

| Line | Content / 내용 |
|------|----------------|
| 1 | 📂 Directory + Git branch (dirty `*`, ahead/behind `↑↓`) │ Model, CLI version, Output style │ 💻 Memory |
| 2 | 🧠 Context usage (bar) │ Session time + tokens + cost │ 🗄 Cache + Speed |
| 3 | 💰 Today │ Week │ Month usage & costs |

On narrow terminals (e.g. a portrait tablet/mobile-style split pane), the layout above automatically
shrinks — see "Compact Mode" under Customization below.

좁은 터미널(태블릿/모바일처럼 세로로 긴 분할 화면)에서는 위 레이아웃이 자동으로 축약됩니다 —
아래 "Customization" 섹션의 "축약 모드" 참고.

### Example Output / 예시 출력

```
📂 ~/projects/myapp  main* ↑2 │ Opus 4.6  v1.0.44  explanatory  │ 💻 Mem 42%
🧠 Context 45.2K/200K [============--------] 77% │ Session 1.2M $0.12  3h 42m [====------] │ 🗄 87%  12.5K/m
💰 Today 2.1M  $4.32 │ Week 15.8M  $31.20 │ Month 48.2M  $95.50
```

`main*` means uncommitted changes are present; `↑2`/`↓1` show commits ahead/behind the upstream branch (both omitted when there's nothing to report).

`main*`는 커밋되지 않은 변경사항이 있음을, `↑2`/`↓1`은 upstream 브랜치 대비 앞서거나 뒤처진 커밋 수를 의미합니다 (보고할 내용이 없으면 생략).

With `STATUSLINE_UNICODE=1` / Unicode 모드:
```
📂 ~/projects/myapp  main │ Opus 4.6  v1.0.44  explanatory  │ 💻 Mem 42%
🧠 Context 45.2K/200K ▰▰▰▰▰▰▰▰▰▰▰▰▱▱▱▱▱▱▱▱ 77% │ Session 1.2M $0.12  3h 42m ▰▰▰▰▱▱▱▱▱▱ │ 🗄 87%  12.5K/m
💰 Today 2.1M  $4.32 │ Week 15.8M  $31.20 │ Month 48.2M  $95.50
```

Graceful degradation (without ccusage / ccusage 없이):
```
📂 ~/projects/myapp  main │ Opus 4.6  v1.0.44  explanatory  │ 💻 Mem 42%
🧠 Context 45.2K/200K [============--------] 77%
```

---

## Installation / 설치

### One-liner Install / 한 줄 설치

```bash
curl -fsSL https://raw.githubusercontent.com/ahngbeom/claude-statusline/main/install.sh | bash
```

### Manual Install / 수동 설치

1. Download statusline.sh and configure.sh / statusline.sh와 configure.sh 다운로드:
```bash
curl -fsSL https://raw.githubusercontent.com/ahngbeom/claude-statusline/main/statusline.sh \
  -o ~/.claude/statusline.sh
curl -fsSL https://raw.githubusercontent.com/ahngbeom/claude-statusline/main/configure.sh \
  -o ~/.claude/configure.sh
chmod +x ~/.claude/statusline.sh ~/.claude/configure.sh
```

2. Update settings / 설정 업데이트:

Edit `~/.claude/settings.json`:
```json
{
  "statusline": "~/.claude/statusline.sh"
}
```

3. Restart Claude Code / Claude Code 재시작

### npm Install (GitHub Packages)

> **Note:** GitHub Packages requires authentication.
> You need a GitHub [Personal Access Token](https://github.com/settings/tokens) with `read:packages` scope.

1. Configure npm:
   ```bash
   echo "@ahngbeom:registry=https://npm.pkg.github.com" >> ~/.npmrc
   echo "//npm.pkg.github.com/:_authToken=YOUR_TOKEN" >> ~/.npmrc
   ```

2. Install:
   ```bash
   npm install -g @ahngbeom/claude-statusline
   ```

---

## Uninstall / 제거

```bash
curl -fsSL https://raw.githubusercontent.com/ahngbeom/claude-statusline/main/uninstall.sh | bash
```

Or if installed via npm / npm으로 설치한 경우:
```bash
npm uninstall -g @ahngbeom/claude-statusline
```

---

## Requirements / 요구사항

### Required / 필수

- **jq**: JSON parsing / JSON 파싱
  ```bash
  # macOS
  brew install jq

  # Ubuntu/Debian
  sudo apt install jq

  # Fedora
  sudo dnf install jq
  ```

### Recommended / 권장

- **ccusage**: For usage statistics (tokens, costs, session info)
  ```bash
  npm install -g ccusage
  ```
  Or use via npx (automatic) / 또는 npx로 자동 실행

### Optional / 선택

- **gdate**: macOS date compatibility / macOS 날짜 호환
  ```bash
  brew install coreutils
  ```

---

## Color Indicators / 색상 표시

These are the defaults. Both the colors and the percentage cutoffs below are customizable — see
[Color Customization](#color-customization--색상-커스터마이징) and
[Threshold Customization](#threshold-customization--임계값-커스터마이징) under Customization.

아래는 기본값입니다. 색상과 퍼센트 기준값 모두 커스터마이징 가능합니다 — Customization 섹션의
[색상 커스터마이징](#color-customization--색상-커스터마이징), [임계값 커스터마이징](#threshold-customization--임계값-커스터마이징) 참고.

### Context Window / 컨텍스트 윈도우

| Remaining / 남은 용량 | Color / 색상 |
|----------------------|--------------|
| > 40% | 🟢 Mint Green |
| 20-40% | 🟠 Peach |
| < 20% | 🔴 Coral Red |

### Session Time / 세션 시간

| Remaining / 남은 시간 | Color / 색상 |
|----------------------|--------------|
| > 25% | 🟢 Light Green |
| 10-25% | 🟡 Light Yellow |
| < 10% | 🔴 Light Pink |

### Memory Usage / 메모리 사용량

| Usage / 사용량 | Color / 색상 |
|---------------|--------------|
| < 60% | 🟢 Green |
| 60-79% | 🟡 Yellow |
| ≥ 80% | 🔴 Red |

---

## Usage Counters / 사용량 카운터

Line 3의 `Today` / `Week` / `Month` 값은 **[ccusage](https://github.com/ryoppippi/ccusage)** 가 보고하는 **달력 기준** 누적치입니다:

- `Today`: 오늘 자정(로컬 TZ)부터의 사용량
- `Week`: 이번 ISO 달력 주(월요일 시작) 누적
- `Month`: 이번 달력 월 누적

> ⚠️ **Anthropic의 weekly rate limit은 rolling 7-day window** 기반입니다 (2026-05-06 정책 변경 이후에도 유지). 즉 Line 3의 `Week` 표시는 **정책 한도 게이지가 아니라 달력 주간 회고용**입니다. 한도 잔량은 Claude Code 내장 `/status` 명령으로 확인하세요.
>
> Anthropic's weekly rate limit uses a **rolling 7-day window**. The `Week` counter on Line 3 reflects **calendar-week** spend (via ccusage), not progress toward the weekly limit. Use `/status` inside Claude Code for the official limit gauge.

Line 2의 `Session` 시간/토큰은 ccusage가 추적하는 **5시간 rolling window** (active block) 기준입니다. 2026-05-06 정책 변경으로 5시간 한도가 2배로 증가했지만 윈도우 길이(5h) 자체는 동일합니다.

---

## Configuration Interface / 설정 인터페이스

`configure.sh` (installed next to `statusline.sh` in `~/.claude/`) lets each user persist their own
display preferences to `~/.claude/statusline.conf`, instead of exporting environment variables in a
shell profile. An environment variable that's already set always takes priority over the config file.

`configure.sh`(`statusline.sh`와 같은 `~/.claude/`에 설치됨)로 각 사용자가 자신의 표시 설정을
셸 프로필에 환경변수를 export하는 대신 `~/.claude/statusline.conf`에 영구 저장할 수 있습니다.
이미 설정된 환경변수는 항상 설정 파일보다 우선합니다.

Running `configure.sh` with no arguments on a real terminal opens a full arrow-key TUI: a single
scrollable list of every setting (grouped by category) with a "Live Preview" panel — `statusline.sh`
rendered with your current settings — pinned at the top of the screen the whole time, updated immediately
after every change instead of scrolling away.

`configure.sh`를 인자 없이 실행하면 실제 터미널에서는 화살표 키로 조작하는 풀 TUI가 열립니다: 카테고리별로
묶인 전체 설정을 하나의 스크롤 목록으로 보여주고, 화면 상단에 "Live Preview" 패널(현재 설정 그대로
렌더링된 `statusline.sh` 결과)이 항상 고정되어 값을 바꿀 때마다 그 자리에서 즉시 갱신됩니다.

| Key / 키 | Action / 동작 |
|----------|----------------|
| `↑` `↓` | Move the cursor / 커서 이동 |
| `PgUp` `PgDn` | Move a page at a time / 페이지 단위 이동 |
| `Enter` / `Space` | Toggle an on/off field, or open exact-value entry for others / on-off 필드는 즉시 전환, 나머지는 정확한 값 입력창 |
| `←` `→` | Nudge a color/percent value by ±1 / 색상·퍼센트 값을 ±1씩 조정 |
| `r` | Reset the current field to its default / 현재 항목을 기본값으로 리셋 |
| `R` | Reset everything (with confirmation) / 전체 리셋(확인 후) |
| `q` / `Esc` | Quit / 종료 |

Piped/non-interactive input (scripts, CI) and `configure.sh menu` explicitly both fall back to a simpler
numbered menu instead — same "Live Preview" panel, but redrawn after each screen rather than pinned.

파이프/비대화형 입력(스크립트, CI)이나 `configure.sh menu`를 명시적으로 실행하면 더 단순한 번호 메뉴로
대신 동작합니다 — 같은 "Live Preview" 패널을 보여주지만 화면마다 다시 그려지는 방식이며 고정되지는
않습니다.

```bash
~/.claude/configure.sh              # full arrow-key TUI on a real terminal (numbered menu otherwise)
~/.claude/configure.sh menu         # force the numbered menu even on a real terminal
~/.claude/configure.sh list         # show every setting: effective value + source (env/config/default)
~/.claude/configure.sh set STATUSLINE_SHOW_WEEK 0
~/.claude/configure.sh get STATUSLINE_SHOW_WEEK
~/.claude/configure.sh unset STATUSLINE_SHOW_WEEK   # revert to default
~/.claude/configure.sh reset -y                     # remove the whole config file
~/.claude/configure.sh preview                      # render statusline.sh with current settings
```

## Customization / 커스터마이징

Use `configure.sh` above, or edit `~/.claude/statusline.sh` directly for anything not exposed there:

위 `configure.sh`를 사용하거나, 거기서 다루지 않는 항목은 `~/.claude/statusline.sh`를 직접 편집하세요:

### Environment Variables / 환경 변수

| Variable | Effect |
|----------|--------|
| `NO_COLOR=1` | Disable ANSI colors / 색상 비활성화 |
| `STATUSLINE_UNICODE=1` | Use `▰▱` block chars instead of `=-` (may misalign in some terminals) |
| `STATUSLINE_MAX_CONTEXT=<tokens>` | Override the context window size used by the JSONL fallback (older Claude Code without the `context_window` stdin field), e.g. for a new model not yet recognized by `get_max_context()` / `context_window` stdin 필드가 없는 구버전에서 fallback 컨텍스트 크기를 오버라이드 (신규 모델 즉시 대응용) |
| `STATUSLINE_HIDE_COST=1` | Hide session cost (Line 2) and all of Line 3 (Today/Week/Month) — for orgs that don't want cost exposed in the terminal / Line 2의 세션 비용과 Line 3 전체(Today/Week/Month)를 숨김 (비용 노출을 꺼리는 조직용) |
| `STATUSLINE_COMPACT=1` / `=0` | Force the compact layout on or off, overriding `$COLUMNS` auto-detection / 터미널 폭과 무관하게 축약 레이아웃을 강제 on/off |
| `STATUSLINE_COMPACT_WIDTH=<cols>` | Auto-compact trigger threshold, default `80` — compact mode kicks in when `$COLUMNS` is below this / 자동 축약 전환 기준 폭 (기본값 80) |
| `STATUSLINE_CONFIG_FILE=<path>` | Override the `~/.claude/statusline.conf` path read/written by `configure.sh` / `configure.sh`가 읽고 쓰는 설정 파일 경로 오버라이드 |

### Per-line Display Toggles / 라인별 표시 토글

All default to `1` (shown); set to `0` to hide. `STATUSLINE_SHOW_GIT=0`/`STATUSLINE_SHOW_MEM=0` also skip the underlying git/memory subprocess call, not just the rendering.

전부 기본값 `1`(표시)이며, `0`으로 설정하면 숨겨집니다. `STATUSLINE_SHOW_GIT=0`/`STATUSLINE_SHOW_MEM=0`은 렌더링뿐 아니라 해당 git/메모리 서브프로세스 호출 자체도 건너뜁니다.

| Variable | Hides |
|----------|-------|
| `STATUSLINE_SHOW_GIT=0` | Line 1 git branch segment entirely / Line 1 git 브랜치 세그먼트 전체 |
| `STATUSLINE_SHOW_GIT_STATUS=0` | Only the dirty(`*`)/ahead-behind(`↑↓`) markers (branch name stays) / dirty·ahead-behind 표시만 (브랜치명은 유지) |
| `STATUSLINE_SHOW_CC_VERSION=0` | Line 1 CLI version (`v1.0.44`) |
| `STATUSLINE_SHOW_OUTPUT_STYLE=0` | Line 1 output style |
| `STATUSLINE_SHOW_MEM=0` | Line 1 `💻 Mem NN%` |
| `STATUSLINE_SHOW_SESSION=0` | Line 2 Session segment (tokens/cost/time/bar) |
| `STATUSLINE_SHOW_CACHE=0` | Line 2 `🗄 NN%` cache hit rate |
| `STATUSLINE_SHOW_SPEED=0` | Line 2 tokens/min |
| `STATUSLINE_SHOW_TODAY=0` | Line 3 Today |
| `STATUSLINE_SHOW_WEEK=0` | Line 3 Week |
| `STATUSLINE_SHOW_MONTH=0` | Line 3 Month |

### Color Customization / 색상 커스터마이징

Each rendered element's [xterm 256-color](https://www.ditig.com/256-colors-cheat-sheet) code can be
overridden individually. An out-of-range or non-numeric value silently falls back to the default (same
graceful-degradation contract as the rest of the script); `NO_COLOR=1` still disables all color output
regardless of these.

각 렌더링 요소의 [xterm 256색](https://www.ditig.com/256-colors-cheat-sheet) 코드를 개별적으로
오버라이드할 수 있습니다. 범위를 벗어나거나 숫자가 아닌 값은 조용히 기본값으로 폴백합니다(스크립트의
다른 부분과 동일한 graceful-degradation 원칙). `NO_COLOR=1`이 설정되면 이 값들과 무관하게 색상 출력
전체가 비활성화됩니다.

| Variable | Default | Element |
|----------|---------|---------|
| `STATUSLINE_COLOR_DIR` | 117 | Line 1 directory |
| `STATUSLINE_COLOR_MODEL` | 147 | Line 1 model name |
| `STATUSLINE_COLOR_GIT` | 150 | Line 1 git branch |
| `STATUSLINE_COLOR_CC_VERSION` | 249 | Line 1 CLI version |
| `STATUSLINE_COLOR_OUTPUT_STYLE` | 245 | Line 1 output style |
| `STATUSLINE_COLOR_SEP` | 240 | Separator character (all lines) |
| `STATUSLINE_COLOR_CACHE` | 120 | Line 2 cache hit rate / tokens-per-min |
| `STATUSLINE_COLOR_TODAY` | 153 | Line 3 Today |
| `STATUSLINE_COLOR_WEEK` | 183 | Line 3 Week |
| `STATUSLINE_COLOR_MONTH` | 216 | Line 3 Month |
| `STATUSLINE_COLOR_CTX_OK` / `_WARN` / `_CRIT` | 158 / 215 / 203 | Context bar, 3-tier by remaining % (see `STATUSLINE_THRESHOLD_CTX_*` below) |
| `STATUSLINE_COLOR_SESSION_OK` / `_WARN` / `_CRIT` | 194 / 228 / 210 | Session segment, 3-tier by remaining % |
| `STATUSLINE_COLOR_MEM_OK` / `_WARN` / `_CRIT` | 120 / 220 / 196 | Line 1 Mem indicator, 3-tier by used % |

### Icon Customization / 아이콘 커스터마이징

| Variable | Default | Element |
|----------|---------|---------|
| `STATUSLINE_ICON_DIR` | 📂 | Line 1 directory prefix |
| `STATUSLINE_ICON_CONTEXT` | 🧠 | Line 2 context segment prefix |
| `STATUSLINE_ICON_COST` | 💰 | Line 3 (and compact Line 3) cost segment prefix |
| `STATUSLINE_ICON_CACHE` | 🗄 | Line 2 cache hit rate prefix |
| `STATUSLINE_ICON_MEM` | 💻 | Line 1 memory indicator prefix |

### Threshold Customization / 임계값 커스터마이징

The percentage cutoffs that pick which 3-tier color renders — see the "Color Indicators" section above
for what each tier means.

어느 3단계 색상을 쓸지 결정하는 퍼센트 기준값입니다 — 각 단계의 의미는 위 "Color Indicators" 섹션
참고.

| Variable | Default | Meaning |
|----------|---------|---------|
| `STATUSLINE_THRESHOLD_CTX_WARN` / `_CRIT` | 40 / 20 | Context remaining % at/below which the bar turns warn/crit-colored |
| `STATUSLINE_THRESHOLD_MEM_WARN` / `_CRIT` | 60 / 80 | Memory used % at/above which Mem turns warn/crit-colored |
| `STATUSLINE_THRESHOLD_SESSION_WARN` / `_CRIT` | 25 / 10 | Session remaining % at/below which Session turns warn/crit-colored |

### Separator Character / 구분자 문자

| Variable | Default | Effect |
|----------|---------|--------|
| `STATUSLINE_SEP_CHAR` | `│` | Replaces the separator character between segments on every line / 모든 라인의 세그먼트 구분자 문자 교체 |

### Compact Mode / 축약 모드

Claude Code >= v2.1.153 sets `$COLUMNS`/`$LINES` to the real terminal size before running the
statusline script (stdout is captured, so `tput cols`-style detection doesn't work from inside the
script). When `$COLUMNS` is narrower than `STATUSLINE_COMPACT_WIDTH` (default 80 — e.g. a portrait
tablet/mobile-style split terminal), the statusline automatically switches to a shorter layout:
directory basename only, no CLI version/output style/Mem on Line 1, no "Context" label word and a
narrower bar on Line 2, and Line 3 collapsed to just session cost/time + today's cost (no token
counts, no Week/Month, no cache hit rate/speed).

Claude Code >= v2.1.153는 스크립트 실행 직전에 `$COLUMNS`/`$LINES`를 실제 터미널 크기로 설정해줍니다
(stdout이 캡처되므로 `tput cols` 방식은 스크립트 내부에서 동작하지 않습니다). `$COLUMNS`가
`STATUSLINE_COMPACT_WIDTH`(기본값 80) 미만이면 — 예: 태블릿/모바일처럼 세로로 긴 분할 터미널 —
자동으로 축약 레이아웃으로 전환됩니다: 디렉터리는 basename만, Line 1의 CLI 버전/output style/Mem
생략, Line 2는 "Context" 라벨 없이 좁은 바, Line 3는 세션 비용/시간 + 오늘 비용만 남기고 토큰
수·Week/Month·캐시 적중률/속도는 생략됩니다.

```
📂 myapp  main*↑2 │ Opus 4.6
🧠 45.2K/200K [====----] 77%
💰 Sess $0.12 3h 42m │ Today $4.32
```

Older Claude Code (or when `$COLUMNS` is unset/non-numeric, e.g. manual testing) silently falls back
to the full layout shown above — same graceful-degradation contract as the rest of the script.

구버전 Claude Code이거나 `$COLUMNS`가 없을 때(수동 테스트 등)는 위의 전체 레이아웃으로 조용히
폴백됩니다 — 이 스크립트의 다른 부분과 동일한 graceful-degradation 원칙을 따릅니다.

**Resizing mid-session:** Claude Code only re-runs the statusline script on specific triggers — a new
assistant message, `/compact` finishing, a permission-mode change, or a vim-mode toggle. A bare
terminal resize with none of those isn't one of them, so the layout can keep showing the old width
until the next trigger fires (confirmed by testing: resizing alone, with no message sent, does not
update the statusline). If you want it to react to a resize on its own, add `refreshInterval` (seconds,
minimum `1`) to `statusLine` in `~/.claude/settings.json` so it re-runs on a timer regardless of
triggers:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "refreshInterval": 2
  }
}
```

This re-runs the script every N seconds even while idle (extra background git/ccusage calls), so only
enable it if you need that responsiveness.

**세션 도중 리사이즈:** Claude Code는 새 assistant 메시지, `/compact` 완료, permission mode 변경,
vim mode 토글 — 이 네 가지 트리거가 있을 때만 statusline 스크립트를 재실행합니다. 이 중 아무 것도
없이 터미널 폭만 조정하면 다음 트리거가 발생하기 전까지 레이아웃이 그대로 유지될 수 있습니다
(실측 확인: 메시지 전송 없이 리사이즈만 해서는 statusline이 바뀌지 않음). 리사이즈에 즉시 반응하게
하려면 `~/.claude/settings.json`의 `statusLine`에 `refreshInterval`(초 단위, 최소 `1`)을 추가해
트리거와 무관하게 주기적으로 재실행되게 하세요(위 JSON 예시 참고). 유휴 상태에서도 N초마다
스크립트가 다시 실행되어(git/ccusage 조회 포함) 백그라운드 부하가 약간 늘어나므로, 필요할 때만
켜는 것을 권장합니다.

### Modify Progress Bar Width / 프로그레스 바 너비 수정

Find calls to `progress_bar` and change the width:

```bash
progress_bar "$pct" 20  # Context bar (default 20)
progress_bar "$pct" 10  # Session bar (default 10)
```

### Cache TTL / 캐시 유효시간

Modify `CACHE_TTL` variable (in seconds):
```bash
CACHE_TTL=120  # Default is 60 seconds
```

---

## How It Works / 작동 방식

1. **Context Calculation**: Reads `context_window` from stdin (Claude Code >= v17.2.0) as the primary source. Falls back to session JSONL files for older versions.
2. **Session Cost**: Reads real-time `cost.total_cost_usd` from stdin, with ccusage blocks data as fallback.
3. **Usage Statistics**: Integrates with [ccusage](https://github.com/anthropics/ccusage) for daily/weekly/monthly metrics.
4. **Caching**: Background caching prevents UI delays (60s TTL). Cache misses show a placeholder without blocking.
5. **Memory Indicator**: Reads system memory usage (macOS via `vm_stat`, Linux via `/proc/meminfo`).

---

## Troubleshooting / 문제 해결

### Statusline not showing / 상태줄이 표시되지 않음

1. Check if `statusline.sh` exists and is executable:
   ```bash
   ls -la ~/.claude/statusline.sh
   ```

2. Verify settings.json:
   ```bash
   cat ~/.claude/settings.json | jq '.statusline'
   ```

3. Restart Claude Code

### Usage data not showing / 사용량 데이터가 표시되지 않음

1. Install ccusage:
   ```bash
   npm install -g ccusage
   ```

2. Verify ccusage works:
   ```bash
   ccusage blocks --json
   ```

### Context showing "···" / 컨텍스트가 "···"로 표시됨

This is normal for new sessions. Context data appears after the first API response.

새 세션에서는 정상입니다. 첫 번째 API 응답 후 컨텍스트 데이터가 표시됩니다.

---

## Credits / 크레딧

- Inspired by [cc-statusline](https://www.npmjs.com/package/@chongdashu/cc-statusline)
- Uses [ccusage](https://github.com/anthropics/ccusage) for usage statistics

---

## License

MIT License - see [LICENSE](LICENSE)

---

## Contributing / 기여

Issues and pull requests are welcome!

이슈와 풀 리퀘스트를 환영합니다!

### Running tests / 테스트 실행

```bash
# Requires bats-core: brew install bats-core (or npm install -g bats)
bats tests/

# Requires shellcheck: brew install shellcheck
shellcheck statusline.sh configure.sh install.sh uninstall.sh scripts/*.sh tests/test_helper.bash
```
