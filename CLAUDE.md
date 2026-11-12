# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Claude Code CLI용 3줄 컴팩트 statusline 스크립트. 세션 컨텍스트 사용량, 토큰/비용 통계, Git 정보를 터미널에 실시간 표시한다. 순수 Bash 스크립트이며, 회귀 방지를 위해 `bats-core`(경량 테스트)와 `shellcheck`(린트)를 CI에서만 사용한다 (별도 빌드 도구는 없음).

## Development

```bash
# 테스트 실행 (bats-core 필요: brew install bats-core 또는 npm install -g bats)
bats tests/

# 린트 실행 (shellcheck 필요: brew install shellcheck)
shellcheck statusline.sh configure.sh install.sh uninstall.sh scripts/*.sh bin/git-mr shell/git-prompt.sh tests/test_helper.bash

# 로컬 수동 테스트 (mock stdin으로 statusline 실행)
echo '{"workspace":{"current_dir":"/tmp/test"},"model":{"display_name":"Opus 4.6"},"session_id":"test-123","version":"1.0.44","output_style":{"name":"explanatory"}}' | bash statusline.sh

# context_window 필드 포함 테스트 (Claude Code >= v17.2.0)
echo '{"workspace":{"current_dir":"/tmp/test"},"model":{"display_name":"Opus 4.6"},"session_id":"test-123","version":"1.0.44","output_style":{"name":"explanatory"},"context_window":{"total_input_tokens":45000,"context_window_size":200000},"cost":{"total_cost_usd":0.123}}' | bash statusline.sh

# NO_COLOR 모드 테스트
echo '{}' | NO_COLOR=1 bash statusline.sh

# Unicode progress bar 테스트
echo '{}' | STATUSLINE_UNICODE=1 bash statusline.sh

# 실제 Claude Code에 연결해서 테스트 (statusline.sh를 ~/.claude/에 복사 후 재시작)
cp statusline.sh ~/.claude/statusline.sh

# 사용자별 설정 CLI/TUI 로컬 테스트 (별도 설정 파일로 격리)
STATUSLINE_CONFIG_FILE=/tmp/statusline.conf ./configure.sh list
STATUSLINE_CONFIG_FILE=/tmp/statusline.conf ./configure.sh set STATUSLINE_SHOW_WEEK 0
```

## Architecture

### 핵심 흐름

```
Claude Code CLI → stdin(세션 JSON) → statusline.sh → stdout(3줄 ANSI 출력)
```

`statusline.sh`는 Claude Code가 매 렌더링마다 호출하며, 4개 데이터 소스를 조합한다:

| 소스 | 위치 | 출력 라인 | 우선순위 |
|------|------|-----------|----------|
| stdin JSON | Claude Code가 전달 | Line 1 (dir, model, version, style), Line 2 (session cost) | Primary |
| stdin context_window | Claude Code >= v17.2.0 | Line 2 (컨텍스트 토큰) | Primary |
| 세션 JSONL | `~/.claude/projects/-{encoded-dir}/{session-id}.jsonl` 마지막 20줄 | Line 2 (컨텍스트 토큰) | Fallback |
| ccusage 캐시 | `~/.claude/stats-cache.json` (TTL 60초, 백그라운드 갱신) | Line 2 (세션), Line 3 (비용) | — |
| Git | `git --no-optional-locks status --porcelain=v2 --branch --show-stash` 1회 (+ 상세 모드면 `rev-parse --git-dir` 1회) | Line 1 (브랜치명·dirty·ahead/behind·상세 개수) | — |
| stdin `pr` | Claude Code가 전달 (`number`/`url`/`review_state`/`kind`) | Line 1 (PR/MR 번호, 리뷰 상태 색) | Primary |
| stdin `effort.level`/`thinking.enabled`/`fast_mode` | Claude Code가 전달 | Line 1 (모델명 뒤 `(high, thinking, fast)`) | 있으면 `⌘`의 기동 시점 `effort:`보다 우선 |
| 세션 JSONL `perTurnEffort` | `transcript_path` 마지막 50줄, `STATUSLINE_SHOW_TURN_EFFORT=1`일 때만 | Line 1 (`turn:xhigh`) | 세션 레벨과 다를 때만 |
| git-mr 캐시 | `bin/git-mr --cached` (`$XDG_CACHE_HOME/git-mr/`, TTL 120초, 백그라운드 갱신) | Line 1 (파이프라인 표시) | `pr`과 같은 PR/MR일 때만 |
| 부모 프로세스 argv | `/proc/<pid>/cmdline` (Linux) 또는 `ps -o ppid=,args=` (macOS/BSD) | Line 1 (세션 기동 CLI 플래그) | — |
| 사용자 설정 파일 | `~/.claude/statusline.conf` (`configure.sh`가 씀) | 전체 (표시 여부/색상/compact 등) | env var보다 후순위 |
| 세션별 상태 파일 | `~/.claude/statusline-state/<session_id>` (이 스크립트가 직접 씀) | Line 2 (직전 질문 변화량 `+4.2K`/`+$0.03`) | — |

`statusline.sh`는 stdout 3줄 외에 side-channel 출력도 하나 만든다: stdin의 `rate_limits`(있으면)를
그대로 `~/.claude/rate-limits-cache.json`에 써서 남긴다. 이 스크립트 자신은 이 값을 렌더링에 쓰지
않는다 — cc-menutor 같은 외부 도구가 서버 실측 리셋 시각(5시간/7일 rate-limit 윈도우)을 읽어가는
용도다. 자세한 계약은 아래 "stdin JSON 스키마"와 `# ---- rate limits cache` 섹션 참고.

### stdin JSON 스키마

Claude Code가 전달하는 입력. `jq`로 한 번에 파싱하며 Unit Separator(`\u001f`)로 분리:

```json
{
  "workspace": { "current_dir": "/Users/..." },
  "model": { "display_name": "Opus 4.6" },
  "session_id": "uuid-string",
  "version": "1.0.44",
  "output_style": { "name": "explanatory" },
  "context_window": {
    "total_input_tokens": 45000,
    "context_window_size": 200000
  },
  "cost": { "total_cost_usd": 0.123 },
  "transcript_path": "/Users/.../.claude/projects/.../uuid.jsonl",
  "rate_limits": {
    "five_hour": { "used_percentage": 23.5, "resets_at": 1738425600 },
    "seven_day": { "used_percentage": 41.2, "resets_at": 1738857600 }
  }
}
```

`context_window`와 `cost`는 Claude Code >= v17.2.0에서 제공. 없으면 JSONL fallback으로 컨텍스트를 계산하고, 세션 비용은 ccusage blocks 데이터를 사용한다.

**stdin에 없는 것 (재조사 방지용 기록, 2026-07-30 v2.1.220 기준):** `permission_mode`와 **모든 CLI
인자**(`-c`/`--resume`/`--model`/`--permission-mode` 등)는 statusline stdin JSON에 **없다**. 공식 문서
(code.claude.com/docs/en/statusline)의 전체 스키마에도 없고, 바이너리의 statusline 페이로드 생성 함수를
확인해 보면 공통 훅 헬퍼(`session_id`/`transcript_path`/`cwd`/`prompt_id`/`permission_mode`를 반환)를
**인자 없이** 호출하기 때문에 `permission_mode`가 `undefined`가 되어 `JSON.stringify`에서 탈락한다.
그래서 세션 기동 옵션은 부모 프로세스 argv에서 읽는다 (아래 `# ---- session invocation` 섹션).
"세션이 어떤 옵션으로 켜졌나"에 stdin으로 답할 수 있는 필드는 `agent.name`(`--agent`),
`worktree.*`(`--worktree`), `workspace.added_dirs`(`--add-dir`), `session_name`(`--name`//`rename`),
`fast_mode`, `effort.level`, `thinking.enabled`, `vim.mode` 정도이며, 이 중 `fast_mode`/`effort.level`/
`thinking.enabled`만 모델 라벨에 쓴다.

`effort.level`은 **세션 레벨**이다(`CLAUDE_CODE_EFFORT_LEVEL` > `/effort` > `--effort` > 설정 > 모델 기본값).
공식 문서가 `ultrathink`(그 턴만 `xhigh`)·skill `effort` frontmatter(그 턴 끝까지)·subagent effort는
여기에 반영되지 않는다고 명시한다. subagent effort는 별도 설정 `subagentStatusLine`의 `tasks[].effort`에만
있다. 턴 단위 실제 effort는 transcript JSONL의 assistant 레코드 `effort`/`perTurnEffort`(문서화되지 않은
내부 필드)에만 보인다 — 2026-11-12 v2.1.322 실측: 세션 `high`에서 ultrathink 턴은 두 필드 모두 `xhigh`로
기록됨(다음 일반 턴은 다시 `high`). skill effort가 같은 필드에 찍히는지는 미확인. `STATUSLINE_SHOW_TURN_EFFORT`
(opt-in)가 이 필드를 쓴다 — 비공식 필드라 기본값으로 켜지 말 것.

`workspace.project_dir`(세션을 시작한 디렉터리)와 `prompt_id`(처리 중인 사용자 프롬프트 UUID, 첫 입력
전에는 없음)는 공식 문서 스키마에 있고 이 스크립트가 쓴다: 전자는 경로 축약 때 프로젝트 폴더명을
보존하는 기준, 후자는 변화량을 질문 단위로 묶는 키. 실제 페이로드에 `prompt_id`가 오는지는 아직
실측하지 않았다 — 위 공통 훅 헬퍼가 인자 없이 호출된다는 관찰과 같은 이유로 빠질 수도 있으므로,
없으면 변화량이 "마지막 단계 하나" 단위로 조용히 폴백하도록 되어 있다.

`rate_limits`는 Claude.ai Pro/Max 구독자에 한해, 세션 중 첫 API 응답 이후부터 제공된다(API 키
사용자나 첫 응답 이전에는 없거나 `five_hour`/`seven_day` 중 한쪽만 있을 수 있음). `used_percentage`는
0~100, `resets_at`은 그 윈도우가 리셋되는 UTC epoch초. `statusline.sh`는 이 값을 렌더링에 쓰지 않고
`~/.claude/rate-limits-cache.json`에 원본 그대로(변형 없이) 저장만 한다 — 없거나 비어 있으면 기존
캐시 파일을 건드리지 않고 조용히 건너뛴다(일시적으로 값이 빠진 렌더 한 번 때문에 여전히 유효한
이전 값을 지우지 않기 위함).

`$COLUMNS`/`$LINES`는 위 stdin JSON에 포함되지 않는다 — Claude Code >= v2.1.153이 이 스크립트를
실행하기 **직전에 환경변수로 주입**하는 값이다(캡처된 stdout에는 실제 터미널이 연결되어 있지 않아
`tput cols` 등 직접 조회가 동작하지 않으므로). `is_compact_mode()`가 이 값으로 좁은 터미널(태블릿/
모바일 분할 화면 등)을 자동 감지해 축약 레이아웃으로 전환한다 — 자세한 내용은 `# ---- compact mode
detection` 섹션과 README "Compact Mode" 참고. 구버전 Claude Code나 `$COLUMNS` 미설정 시에는 기존
전체 레이아웃으로 조용히 폴백한다.

`is_compact_mode()`는 stateless라 실행될 때마다 항상 그 시점 `$COLUMNS`를 정확히 판정하지만, 실행
자체는 Claude Code가 트리거해야 일어난다. 공식 문서 기준(2026-11 확인) 재실행 트리거는 세션 시작 /
새 assistant 메시지 / `/compact` 완료 / permission mode 변경 / vim mode 토글 / `statusLine` 명령 변경 /
rate-limit `resets_at` 도달 / prompt cache `expires_at` 도달(+ 설정 시 `refreshInterval` 타이머)이고,
300ms 디바운스가 걸리며 실행 중에 새 트리거가 오면 진행 중인 스크립트는 **취소**된다.
**순수 터미널 리사이즈는 이 목록에 없다** — 실측으로 확인됨: 세션 도중 다른 트리거 없이 창 폭만
줄이면 statusline이 즉시 바뀌지 않고 다음 트리거까지 이전 레이아웃을 유지한다. 이는 `statusline.sh`
버그가 아니라 Claude Code 호스트의 재실행 스케줄링 특성이라 스크립트 쪽에서 고칠 수 없다 — 즉시
반영이 필요하면 `~/.claude/settings.json`의 `statusLine.refreshInterval`(초 단위)을 안내할 것(README
"Compact Mode" 참고).

### 사용자 설정 파일 (`~/.claude/statusline.conf`)

`configure.sh`(저장소 루트, `statusline.sh`와 나란히 설치됨)로 사용자가 대화형 메뉴 또는
`configure.sh set/get/unset/list/reset/path` CLI로 자신의 표시 설정을 영구 저장할 수 있다.
`statusline.sh`는 시작 시(`STATUSLINE_CONFIG_FILE` 환경변수로 경로 오버라이드 가능, 기본
`~/.claude/statusline.conf`) 이 파일을 `KEY=VALUE` 줄 단위로 파싱해 읽는다 — `source`하지 않고
28개 키 allowlist에 대해서만 `printf -v`로 대입하며(임의 코드 실행 방지), **이미 설정된 환경변수가
있으면 그 키는 건너뛴다** (env var가 항상 config 파일보다 우선). 서브프로세스를 하나도 만들지
않는다 (순수 bash while-read). `STATUSLINE_COLOR_*`/`STATUSLINE_ICON_*`/`STATUSLINE_THRESHOLD_*`/
`STATUSLINE_SEP_CHAR`는 이 28개와 별개로 prefix-glob arm이 처리하므로, 그 계열에 키를 추가할 때는
로더를 건드리지 않아도 된다 (`configure.sh`의 4개 레지스트리만 갱신).

28개 키는 `configure.sh` 안에서 4가지 타입으로 분류된다 (`_key_type()` 참고):
- **presence**: `NO_COLOR`/`STATUSLINE_UNICODE`/`STATUSLINE_HIDE_COST`/`STATUSLINE_PATH_LINK` — `statusline.sh`가 `-z`/`-n`으로
  검사하므로 "켬"은 `KEY=1`을 쓰고 "끔"은 **키 자체를 삭제**해야 한다 (`KEY=0`을 쓰면 `-z`가
  거짓이 되어 오히려 "켬"으로 해석됨 — `configure.sh`가 이 변환을 대신 처리)
- **tristate**: `STATUSLINE_COMPACT` — `1`/`0`/키 삭제(`$COLUMNS` 자동 감지로 복귀) 3가지
- **numeric**: `STATUSLINE_COMPACT_WIDTH`, `STATUSLINE_MAX_CONTEXT`, `STATUSLINE_PATH_MAX`
- **bool**: `STATUSLINE_SHOW_*` 17개 + `STATUSLINE_HYPERLINKS` — 값 기반, 기본값 `1`(표시), `0`이면 숨김.
  `STATUSLINE_SHOW_GIT_DETAIL`/`STATUSLINE_SHOW_TURN_EFFORT`만 기본값 `0`(opt-in)이라 `configure.sh`의 `_key_default()`에 명시돼 있다
- **text**: `STATUSLINE_SESSION_CMD` — 임의 문자열이지만 원문 렌더링은 하지 않고
  `_format_session_cmd` 화이트리스트를 통과시키므로 주입 표면이 없다 (`STATUSLINE_ICON_*`/
  `STATUSLINE_SEP_CHAR`도 같은 `text` 타입이지만 그쪽은 `printf %s` 인자로만 쓰인다는 다른 근거,
  `STATUSLINE_THEME`은 알려진 테마 이름과 비교만 하고 출력하지 않는다는 또 다른 근거)

`STATUSLINE_SHOW_GIT=0`/`STATUSLINE_SHOW_MEM=0`/`STATUSLINE_SHOW_SESSION_CMD=0`은 렌더링만 숨기는 게
아니라 각각 git 정보 수집(`_gather_git_info`), `get_mem_usage()`, `_gather_session_argv()` 호출 자체를
건너뛰어 서브프로세스를 아낀다 (compact 모드는 Mem과 세션 기동 옵션을 원래 렌더링하지 않으므로 둘 다
`_compact=1`이면 무조건 스킵). `STATUSLINE_SHOW_DELTA=0`은 `~/.claude/statusline-state/` 읽기/쓰기
자체를 건너뛴다. `update_cache_background()`도
`STATUSLINE_SHOW_TODAY`/`WEEK`/`MONTH`가 각각 `0`이면 대응 `ccusage daily/weekly/monthly` 호출을
개별적으로 생략한다 — 단 `ccusage blocks`는 캐시 파일 전체 쓰기를 게이트하는 역할도 겸하므로,
Session/Cache/Speed/Today/Week/Month 여섯 개가 전부 `0`이 아닌 한 항상 실행된다.

### statusline.sh 내부 구조

섹션 마커(`# ---- name ----`)로 구분. `grep -n '# ----' statusline.sh`로 경계 확인:

| 영역 | 마커 | 역할 |
|------|------|------|
| 설정 파일 로더 | `# ---- user config file` | `~/.claude/statusline.conf`를 allowlist 기반으로 파싱, env var 우선 |
| 테마 프리셋 | `# ---- theme presets` | `STATUSLINE_THEME`(현재 `space`)이 비어 있는 `STATUSLINE_COLOR_*`/`ICON_*`/`SEP_CHAR`만 `:=`로 채움. 설정 파일 로더 다음, 색상 변수 앞이어야 개별 설정이 이김. `configure.sh`가 `_apply_theme()`를 sed로 꺼내 실행해 `get`/`list`/TUI에 테마 값을 보여 주므로 함수 이름과 단독 줄 닫는 중괄호를 유지 |
| 색상 변수 | `# ---- pre-computed color variables` | `NO_COLOR` 대응, 서브셸 없이 ANSI 코드 사전 계산 |
| progress bar 문자 | `# ---- progress bar characters` | `STATUSLINE_UNICODE` 여부로 `▰▱` 또는 `=-` 선택 |
| compact mode 감지 | `# ---- compact mode detection` | `$COLUMNS`/`STATUSLINE_COMPACT`/`STATUSLINE_COMPACT_WIDTH`로 `is_compact_mode()` 판정, `_compact` 변수에 저장 |
| 헬퍼 함수 | `# ---- time helpers`, `# ---- pure bash progress bar`, `# ---- pure bash format_tokens` | `to_epoch()`, `progress_bar()`, `format_tokens()`, `get_mem_usage()` 등 순수 bash |
| 디렉터리 표시 헬퍼 | `# ---- directory display (Line 1)` | `_home_tilde()`(앞부분 `$HOME`만 `~`로), `_abbrev_path()`(단계적 fish 축약, project_dir 세그먼트 보존), `_file_url()`(OSC 8용 바이트 단위 percent-encoding — bash 3.2가 0x80 이상 바이트를 음수로 돌려주는 것을 보정). 모두 REPLY 반환, 0포크 |
| 변화량 헬퍼 | `# ---- last-change delta helpers` | `_money_to_e4()`: 달러를 1/10000 단위 정수로 바꿔 차이 계산을 정수 연산으로 유지 |
| 세션 기동 옵션 | `# ---- session invocation (CLI argv)` | `_sc_sanitize()`/`_format_session_cmd()`(순수 bash 화이트리스트, REPLY 반환)와 `_gather_session_argv()`(상위 3단계까지 `claude` 프로세스 argv 탐색, Linux `/proc` 0포크 · macOS `ps` 1포크) |
| 캐싱 레이어 | `# ---- cache helpers for ccusage data` | ccusage 결과 캐시, 4개 명령 병렬 실행, atomic write + lock |
| 입력 파싱 | `# ---- parse input with single jq call` | 단일 jq 호출, Unit Separator(0x1f) 구분자. `rate_limits`도 이 한 번의 jq 호출에서 함께 추출(전용 서브프로세스 추가 없음) |
| rate limits 캐시 | `# ---- rate limits cache` | stdin `rate_limits`를 변형 없이 `~/.claude/rate-limits-cache.json`에 atomic write(외부 소비자용 side-channel — 이 스크립트의 stdout 렌더링과 무관) |
| 컨텍스트 계산 | `# ---- context window calculation` | stdin context_window 우선, JSONL fallback |
| ccusage 통합 | `# ---- ccusage integration` | 일/주/월 통계, 세션 시간, 캐시 히트율 |
| 모델 라벨 | `# ---- model label` (`# ---- memory usage` 다음) | `effort.level`(`^[a-z][a-z0-9_-]{0,11}$`만 통과)·`thinking`·`fast`로 `$_model_label` 조립. compact면 effort만. `STATUSLINE_SHOW_TURN_EFFORT=1`이면 `_last_turn_effort`(`# ---- turn effort (transcript)` 섹션, transcript 마지막 50줄에서 sidechain이 아닌 마지막 assistant 레코드의 `perTurnEffort`, `tail` 1포크)로 `turn:<v>` 추가. 실시간 레벨을 표시하면 `_sc_skip_effort=1`을 세워 `_format_session_cmd`가 `--effort`를 건너뛰게 하므로 아래 세션 기동 옵션 수집보다 **먼저** 있어야 함 |
| 세션 기동 옵션 수집 | `# ---- session invocation` (렌더 직전, `# ---- model label` 다음) | `_compact=0` + `STATUSLINE_SHOW_SESSION_CMD!=0`일 때만 `_gather_session_argv` → `_format_session_cmd` 실행해 `$_session_cmd` 설정 |
| PR/MR | `# ---- pull request / merge request` | stdin `pr`로 `!N`/`#N` 세그먼트 조립, `_link()`(OSC 8, URL 허용 문자만)로 링크. `git-mr`이 PATH에 있고 기록이 같은 PR/MR이면 파이프라인 표시 추가 |
| 직전 질문 변화량 | `# ---- last-change deltas` | 세션별 상태 파일을 `read`로 읽어 검증(source 금지), 기준값은 **이전 `prompt_id`의 마지막 값**(질문 제출은 재실행 트리거가 아니라서 새 prompt_id의 첫 렌더에는 이미 첫 단계가 반영돼 있음). 값이 바뀔 때만 다시 씀. 새 세션 파일을 만들 때만 7일 지난 파일을 백그라운드 `find`로 정리 |
| 디렉터리 표시 조립 | `# ---- directory display` (렌더 직전) | compact면 basename, 아니면 `_abbrev_path`. `STATUSLINE_PATH_LINK`면 **원본 경로**(`current_dir_raw`)로 OSC 8 링크 |
| 렌더링 | `# ---- render statusline` | `$_compact` 값으로 축약/전체 레이아웃 분기 후 3줄 출력 조립 |

### 파일 역할

- **statusline.sh**: 메인 스크립트. `~/.claude/settings.json`에 `"statusLine": {"type": "command", "command": "~/.claude/statusline.sh"}` 형태로 등록 (소문자 `"statusline"` 문자열 키는 Claude Code가 읽지 않는다). stdout 렌더링과 별개로, stdin에 `rate_limits`가 있으면 `~/.claude/rate-limits-cache.json`에도 그대로 옮겨 쓴다(cc-menutor 등 외부 도구용 side-channel). 시작 시 `~/.claude/statusline.conf`(사용자 설정 파일, 아래 참고)도 읽는다
- **bin/git-mr**: 현재 브랜치의 GitLab MR / GitHub PR을 `glab`/`gh`로 조회하는 독립 스크립트 (npm `bin`으로 PATH에 등록, `git mr` 서브커맨드). `--cached`/`--segment`는 네트워크를 건드리지 않고 캐시만 읽으며 오래되면 `setsid`/`nohup`으로 분리한 백그라운드 갱신을 띄운다. `statusline.sh`는 이 파일 없이도 동작해야 한다 (파이프라인 표시만 빠짐). curl 설치기는 이 파일을 설치하지 않는다
- **shell/git-prompt.sh**: bash/zsh 프롬프트용 선택 스니펫. git의 `__git_ps1` + `git-mr --segment=bash|zsh`. 설치기가 건드리지 않으며 README 안내대로 사용자가 직접 source
- **configure.sh**: `statusline.sh`와 나란히 설치되는 독립 CLI/TUI. `~/.claude/statusline.conf`를 읽고 쓴다 (`list`/`get`/`set`/`unset`/`reset`/`path`/`preview` 서브커맨드, 인자 없이 실행하면 대화형 메뉴). 외부 의존성 없는 순수 bash
- **install.sh**: 원라이너 설치 (`curl | bash`). 의존성 확인 → GitHub에서 statusline.sh + configure.sh 다운로드 → settings.json의 `statusLine` 객체(`type`/`command`) 설정. `padding`/`refreshInterval` 등 기존 `statusLine` 필드는 유지하고, 1.11.1 이전 설치기가 쓰던 소문자 `statusline` 키는 지운다. 기존 settings.json이 있으면 `.backup` 생성. 기존 `~/.claude/statusline.sh`의 2번째 줄이 `# claude-statusline - `로 시작하지 않으면(사용자 스크립트) `statusline.sh.backup-<timestamp>`로 보존한 뒤 교체
- **uninstall.sh**: `~/.claude/statusline.sh`, `~/.claude/configure.sh`, `~/.claude/stats-cache.json`, `~/.claude/rate-limits-cache.json`, `~/.claude/statusline.conf`, `~/.claude/statusline-state/` 삭제, settings.json에서 이 스크립트를 가리키는 `statusLine`과 소문자 `statusline` 키 제거. `statusline.sh`가 claude-statusline 것이 아니면 파일과 `statusLine` 둘 다 남긴다
- **scripts/postinstall.sh**: npm `postinstall` 훅. `npm install`로 패키지 설치 시 install.sh와 동일한 역할 수행 (statusline.sh + configure.sh 복사 + settings.json 등록)
- **scripts/preuninstall.sh**: npm `preuninstall` 훅. `npm uninstall`로 패키지 제거 시 uninstall.sh와 동일한 역할 수행

> ⚠️ **install.sh/uninstall.sh ↔ scripts/postinstall.sh/preuninstall.sh 쌍은 각자 독립 구현이라 함께 수정해야 한다.** curl 원라이너(`install.sh`)는 `check_deps()`에서 jq 부재 시 즉시 종료하지만, npm 훅(`scripts/postinstall.sh`)은 `npm install` 자체를 실패시키지 않기 위해 jq 부재 시 경고만 출력하고 계속 진행한다 — 이 차이는 의도된 것이므로 "동기화"한답시고 없애지 말 것. 두 파일이 완전히 공유 코드를 쓰지 않는 이유는 `install.sh`가 curl로 단일 파일만 받아 실행되는 구조라 별도 lib 파일을 참조할 수 없기 때문(YAGNI로 통합 보류). settings.json 갱신/삭제 로직(jq 커맨드 자체)을 바꿀 때는 4개 파일 모두 확인할 것. `configure.sh` 배포(다운로드/복사/삭제) 역시 이 4개 파일 모두에 대칭적으로 들어가 있어야 한다.

- **.github/workflows/publish.yml**: GitHub Release 발행 시 자동 실행. `verify`(버전 3곳 일치) 잡 이후 `publish-github-packages` 잡이 실행되어 GitHub Packages에 발행한다. npmjs.com 발행(`publish-npmjs` 잡)은 `NPM_TOKEN` 만료로 v1.3.0/v1.3.1/v1.3.3/v1.3.4/v1.5.0에서 반복적으로 실패해 v1.5.0에서 제거함 — GitHub Packages 단일 발행 구조로 전환
- **.github/workflows/ci.yml**: push/PR마다 실행. `shellcheck` 린트 + `tests/`의 `bats` 테스트

### 성능 설계 원칙

- **서브프로세스 최소화**: ~108개 → ~12개 (v1.1.0)
- 색상 코드, progress bar, 토큰 포맷팅 모두 순수 bash (tr, awk 제거)
- jq 호출 통합: 입력 파싱 6→1, 블록 파싱 8→1, 캐시 파싱 4→1
- ccusage cache miss 시 동기 npx 호출 제거, 백그라운드 전용
- `context_window` stdin 필드 사용 시 JSONL 파일 I/O 완전 제거 (v1.3.0)
- 사용되지 않던 `session_txt`/`fmt_time_hm()` 제거로 세션 렌더링 시 불필요한 `date` 서브프로세스 포크 제거 (v1.3.4)
- `STATUSLINE_SHOW_GIT=0`/`STATUSLINE_SHOW_MEM=0` 설정 시 git 수집/`get_mem_usage()` 호출 자체를 스킵, `STATUSLINE_SHOW_TODAY`/`WEEK`/`MONTH=0` 설정 시 `update_cache_background()`의 대응 `ccusage` 백그라운드 호출을 개별 스킵 (v1.8.0)
- 세션 기동 옵션은 Linux `/proc/<pid>/cmdline`+`/proc/<pid>/stat`을 순수 bash로 읽어 **0포크**, macOS/BSD는 `ps -o ppid=,args=` 한 번으로 부모 argv와 조부모 PID를 동시에 얻어 통상 **1포크**. compact 모드나 `STATUSLINE_SHOW_SESSION_CMD=0`이면 탐색 자체를 스킵. `ps`에 `with_timeout`을 걸지 않는 것은 단일 PID 조회이고 가드 자체가 이 설계가 아끼려는 포크를 추가하기 때문 (`vm_stat`/`sysctl`을 가드하지 않는 것과 동일한 판단) (v1.11.0)

## Dependencies

- **필수**: `jq`
- **권장**: `ccusage` (없으면 Line 3 비용 통계 생략, graceful degradation)
- **선택**: `gdate` (macOS coreutils, 없으면 BSD date 또는 Python3 fallback)

## Key Conventions

- 모든 jq 호출은 최소 횟수로 통합 (성능상 단일 호출 선호)
- 필드 구분자로 Unit Separator(`\u001f`) 사용 (탭/공백과 충돌 방지)
- 동적 색상 임계값: 컨텍스트 잔여 ≤20% 빨강, ≤40% 노랑, >40% 초록
- `NO_COLOR` 환경변수 지원 필수
- `STATUSLINE_UNICODE=1` 환경변수로 `▰▱` 블록 문자 활성화 (기본값: ASCII `=-`)
- `STATUSLINE_MAX_CONTEXT=<tokens>` 환경변수로 JSONL fallback 컨텍스트 윈도우 크기 오버라이드 (신규 모델 즉시 대응)
- `STATUSLINE_HIDE_COST=1` 환경변수로 세션 비용(Line 2)과 Line 3 전체 숨김
- `STATUSLINE_COMPACT=1`/`=0` 환경변수로 축약 레이아웃 강제 on/off (미설정 시 `$COLUMNS` 자동 감지)
- `STATUSLINE_COMPACT_WIDTH=<cols>` 환경변수로 자동 축약 전환 기준 폭 오버라이드 (기본값 80)
- `STATUSLINE_SHOW_*=1/0` 17개 환경변수(GIT/GIT_STATUS/GIT_DETAIL/PR/EFFORT/TURN_EFFORT/CC_VERSION/OUTPUT_STYLE/MEM/SESSION_CMD/SESSION/CACHE/SPEED/DELTA/TODAY/WEEK/MONTH)로 라인별 세그먼트 표시 여부 개별 제어 (기본값 1=표시, `0`이면 숨김이면서 해당 서브프로세스 호출도 스킵)
- `STATUSLINE_SESSION_CMD=<cmd>` 환경변수로 부모 프로세스 argv 자동 탐색을 건너뛰고 기동 명령어를 직접 지정 (래퍼/멀티플렉서가 프로세스 체인을 3단계 넘게 늘려 자동 탐색이 실패하는 환경의 탈출구 겸, 골든 테스트의 플랫폼 독립 seam — 원문 렌더링이 아니라 자동 탐색과 동일한 화이트리스트를 통과한다)
- 위 모든 env var는 `~/.claude/statusline.conf`(`configure.sh`가 관리)로도 설정 가능하며, 이미 설정된 env var가 항상 config 파일 값보다 우선함
- ccusage 없이도 Line 1~2는 정상 동작해야 함 (graceful degradation)
- Git 세그먼트는 전체 레이아웃에서 브랜치 뒤 괄호 안에 **단어로 설명된 개수**를 쓴다: `main (3 uncommitted, ↑2 to push, ↓1 to pull)`, `STATUSLINE_SHOW_GIT_DETAIL=1`이면 `main (rebasing, 1 conflicted, 2 staged, 1 modified, 3 untracked, 1 stashed, ↑1 to push)`. 순서는 진행 중인 작업 → 충돌 → 작업 트리 개수 → stash → push/pull(급한 것부터). detached HEAD는 `detached <짧은 해시>`. compact 모드에서만 짧은 기호(`main* ↑2↓1`)를 쓴다 — `+2 ~1 ?3 $1 REBASE` 같은 기호만으로는 의미를 알 수 없다는 사용자 피드백 때문이므로 전체 레이아웃을 기호로 되돌리지 말 것. upstream 미설정 시 push/pull은 조용히 생략됨 (graceful degradation과 동일한 원칙)
- 테마(`STATUSLINE_THEME`)는 `# ---- theme presets`의 `case`에 `: "${KEY:=값}"` 형태로만 추가한다. 테마가 바꾸는 것은 색·아이콘·구분자뿐이며 git 세그먼트의 단어 표현은 테마로 바꾸지 않는다(위 규칙). `space`의 색 번호와 기호는 [shell-prompt](https://github.com/Ahngbeom/shell-prompt)의 `themes/space.sh`와 같은 세계관을 공유하므로 한쪽을 바꾸면 다른 쪽도 맞출 것. 아이콘은 East Asian Width가 `N`인 문자만 쓴다(`A`는 CJK 설정 터미널에서 2칸이 될 수 있음)
- `STATUSLINE_PATH_MAX=<chars>`(기본 32, `0`이면 축약 안 함)로 Line 1 경로 축약 기준 길이, `STATUSLINE_PATH_LINK=1`로 경로를 OSC 8 `file://` 링크로 감싸 클릭 시 Finder/탐색기로 열기(opt-in — tmux/SSH가 시퀀스를 지우거나 문서가 경고하는 이스케이프 깨짐 위험 때문, `STATUSLINE_HYPERLINKS=0`이면 함께 꺼짐). 표시용 `current_dir`(`~` 치환·축약)과 원본 `current_dir_raw`는 분리되어 있으며 JSONL fallback 경로 계산과 링크는 반드시 원본을 쓸 것
- 지속 애니메이션(스피너, 깜빡임)은 넣지 않는다: 프레임 하나가 스크립트 한 번 실행이고 최소 간격이 1초(`refreshInterval`)이며 새 트리거가 오면 실행이 취소되므로 끊겨 보이고, 문서도 이스케이프가 많은 여러 줄 출력이 깨질 수 있다고 경고한다. 변화를 보여주는 수단은 직전 질문 변화량(`STATUSLINE_SHOW_DELTA`)이다
- context_window stdin 필드를 우선 사용하고, 없을 때만 JSONL fallback
- Line 1의 세션 기동 옵션(`⌘ ...`)은 **기동 시점 argv**다. 따라서 `--permission-mode`는 세션이 시작될 때의 값이며 세션 중 Shift+Tab 변경을 따라가지 않는다 — 이건 버그가 아니라 데이터 출처의 성질이다. 실시간 권한 모드는 stdin에 없고 transcript JSONL의 `{"type":"permission-mode"}` 레코드에는 타임스탬프가 없어 "마지막 값"을 신뢰할 수 없으므로 tail 스캔으로 "고치지" 말 것. 새 플래그를 화이트리스트에 추가할 때는 값이 경로/프롬프트/JSON이면 값은 버리고 존재만 렌더링하고(`+mcp`/`+sysprompt` 패턴), 값을 보여줄 플래그는 반드시 `_sc_sanitize`를 거칠 것 — `tests/unit_session_cmd.bats`가 ANSI/개행/길이 초과 케이스를 검증한다

### Usage counter semantics

- Line 3의 `Today` / `Week` / `Month`는 ccusage가 제공하는 **달력 기준** 누적치 (ISO 주, 달력 월). Anthropic의 weekly rate limit은 **rolling 7-day**라 정책 한도 게이지로 직접 환산되지 않음 — 라벨 의미를 바꿀 때는 README의 "Usage Counters" 섹션도 함께 갱신할 것
- Line 2의 `Session`은 ccusage active block 기준 **5시간 rolling window** (2026-05-06 정책 변경 후에도 윈도우 길이는 동일, capacity만 2배). 단, stdin `rate_limits.five_hour`(서버 실측 `used_percentage`/`resets_at`, Claude.ai Pro/Max 구독자 한정)가 신선(`resets_at`이 아직 미래)하면 그 값이 ccusage 추정치보다 **우선**한다 — ccusage의 활성 블록은 유휴(>5시간 공백) 후 첫 활동 시각 기준 floating anchor 휴리스틱(`.startTime`/`.usageLimitResetTime // .endTime`)이라 서버가 실제로 관리하는 rolling 5시간 윈도우와 어긋날 수 있기 때문 (`~/personal/cc-menutor`가 동일한 문제를 `rate-limits-cache.json`을 통해 간접적으로 보정하는 것과 같은 원인). 오버라이드는 `session_pct`/`rh`/`rm_val`/`session_bar` 네 값에만 적용되고 `tot_tokens`/`cost_usd`/`tpm`/`cache_hit_rate`는 `rate_limits`에 대응 값이 없어 계속 ccusage 값을 쓴다. `rate_limits`가 없거나 stale이면(과거 `resets_at`, API 키 사용자, 세션 첫 응답 이전 등) 조용히 ccusage 추정치로 폴백 — `Session`은 여전히 ccusage 활성 블록(`tot_tokens`)이 있어야만 렌더링된다(게이트는 바뀌지 않음)
- JSONL fallback에서 컨텍스트 사용량을 계산할 때는 `input_tokens + cache_read_input_tokens + cache_creation_input_tokens` 세 값을 모두 더해야 함 (cache_creation도 컨텍스트 윈도우를 점유)
- `get_max_context()`의 모델 패턴 매칭은 **구체적인 패턴이 먼저** 와야 함 (`case`는 첫 매치에서 종료). 1M 컨텍스트 변형 패턴을 일반 Opus/Sonnet 분기보다 위에 유지. 동일한 이유로 `"Claude 3 Haiku"`도 일반 `"Haiku"` 분기보다 위에 있어야 함 (v1.3.4에서 발견된 회귀: 일반 패턴이 먼저 있어 3 Haiku 전용 100000 분기가 죽어있었음) — 새 모델 패턴을 추가할 때는 항상 `tests/unit_get_max_context.bats`로 순서를 검증할 것

## Versioning & Release

- 버전은 `statusline.sh` 헤더의 `# Version: X.Y.Z` 에서 단일 관리
- Annotated 태그 사용: `git tag -a vX.Y.Z -m "메시지"`
- 릴리즈 생성: `gh release create vX.Y.Z --title "vX.Y.Z" --notes "..."`
- 릴리즈 노트 구성: 프로젝트 소개 1줄, Features, Installation one-liner, Changes since 이전 버전, Requirements
- install.sh URL은 `main` 브랜치 고정 (태그별 URL 아님)
- `package.json` 버전은 `statusline.sh` 헤더와 반드시 동기화
- GitHub Release 생성 시 `.github/workflows/publish.yml`이 GitHub Packages에 발행 (npmjs.com 발행은 v1.5.0에서 제거됨 — 아래 참고)
- 릴리즈 전 3곳 버전 일치 확인 필수: `statusline.sh` 헤더, `package.json`, git 태그 (`verify` 잡이 자동 검증하므로 불일치 시 발행 잡이 실행되지 않음)
- 릴리즈 후 `gh run list --workflow=publish.yml --limit 1`로 `publish-github-packages`가 성공했는지 확인할 것
- **npmjs.com 발행은 v1.5.0에서 중단함.** `NPM_TOKEN`이 짧은 주기로 만료되어 v1.3.0/v1.3.1/v1.3.3/v1.3.4/v1.5.0에서 `publish-npmjs` 잡이 반복적으로 실패했고(매번 수동 토큰 재발급 필요), 유지 비용 대비 이점이 낮아 잡 자체를 제거함. npmjs.com에는 1.4.1까지만 남아 있고 이후 버전은 GitHub Packages에서만 제공
- push/PR마다 `.github/workflows/ci.yml`(shellcheck + bats)이 별도로 실행되며, 릴리즈 여부와 무관하게 항상 통과해야 함
- 별도 `CHANGELOG.md`는 두지 않기로 결정함 (2026-07-01). 버전별 변경사항은 `statusline.sh` 헤더 주석 + GitHub Release 노트 2곳으로 충분하며, 세 번째 파일을 추가하면 동기화 부담만 늘어남 (YAGNI)
