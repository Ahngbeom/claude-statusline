# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Claude Code CLI용 3줄 컴팩트 statusline 스크립트. 세션 컨텍스트 사용량, 토큰/비용 통계, Git 정보를 터미널에 실시간 표시한다. 순수 Bash 스크립트이며, 회귀 방지를 위해 `bats-core`(경량 테스트)와 `shellcheck`(린트)를 CI에서만 사용한다 (별도 빌드 도구는 없음).

## Development

```bash
# 테스트 실행 (bats-core 필요: brew install bats-core 또는 npm install -g bats)
bats tests/

# 린트 실행 (shellcheck 필요: brew install shellcheck)
shellcheck statusline.sh install.sh uninstall.sh scripts/*.sh tests/test_helper.bash

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
| Git | `git branch --show-current` | Line 1 (브랜치명) | — |

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

`rate_limits`는 Claude.ai Pro/Max 구독자에 한해, 세션 중 첫 API 응답 이후부터 제공된다(API 키
사용자나 첫 응답 이전에는 없거나 `five_hour`/`seven_day` 중 한쪽만 있을 수 있음). `used_percentage`는
0~100, `resets_at`은 그 윈도우가 리셋되는 UTC epoch초. `statusline.sh`는 이 값을 렌더링에 쓰지 않고
`~/.claude/rate-limits-cache.json`에 원본 그대로(변형 없이) 저장만 한다 — 없거나 비어 있으면 기존
캐시 파일을 건드리지 않고 조용히 건너뛴다(일시적으로 값이 빠진 렌더 한 번 때문에 여전히 유효한
이전 값을 지우지 않기 위함).

### statusline.sh 내부 구조

섹션 마커(`# ---- name ----`)로 구분. `grep -n '# ----' statusline.sh`로 경계 확인:

| 영역 | 마커 | 역할 |
|------|------|------|
| 색상 변수 | `# ---- pre-computed color variables` | `NO_COLOR` 대응, 서브셸 없이 ANSI 코드 사전 계산 |
| progress bar 문자 | `# ---- progress bar characters` | `STATUSLINE_UNICODE` 여부로 `▰▱` 또는 `=-` 선택 |
| 헬퍼 함수 | `# ---- time helpers`, `# ---- pure bash progress bar`, `# ---- pure bash format_tokens` | `to_epoch()`, `progress_bar()`, `format_tokens()`, `get_mem_usage()` 등 순수 bash |
| 캐싱 레이어 | `# ---- cache helpers for ccusage data` | ccusage 결과 캐시, 4개 명령 병렬 실행, atomic write + lock |
| 입력 파싱 | `# ---- parse input with single jq call` | 단일 jq 호출, Unit Separator(0x1f) 구분자. `rate_limits`도 이 한 번의 jq 호출에서 함께 추출(전용 서브프로세스 추가 없음) |
| rate limits 캐시 | `# ---- rate limits cache` | stdin `rate_limits`를 변형 없이 `~/.claude/rate-limits-cache.json`에 atomic write(외부 소비자용 side-channel — 이 스크립트의 stdout 렌더링과 무관) |
| 컨텍스트 계산 | `# ---- context window calculation` | stdin context_window 우선, JSONL fallback |
| ccusage 통합 | `# ---- ccusage integration` | 일/주/월 통계, 세션 시간, 캐시 히트율 |
| 렌더링 | `# ---- render statusline` | 3줄 출력 조립 |

### 파일 역할

- **statusline.sh**: 메인 스크립트. `~/.claude/settings.json`에 `"statusline": "~/.claude/statusline.sh"` 형태로 등록. stdout 렌더링과 별개로, stdin에 `rate_limits`가 있으면 `~/.claude/rate-limits-cache.json`에도 그대로 옮겨 쓴다(cc-menutor 등 외부 도구용 side-channel)
- **install.sh**: 원라이너 설치 (`curl | bash`). 의존성 확인 → GitHub에서 다운로드 → settings.json에 statusline 필드 추가. 기존 settings.json이 있으면 `.backup` 생성
- **uninstall.sh**: `~/.claude/statusline.sh`, `~/.claude/stats-cache.json`, `~/.claude/rate-limits-cache.json` 삭제, settings.json에서 statusline 필드 제거
- **scripts/postinstall.sh**: npm `postinstall` 훅. `npm install`로 패키지 설치 시 install.sh와 동일한 역할 수행 (statusline.sh 복사 + settings.json 등록)
- **scripts/preuninstall.sh**: npm `preuninstall` 훅. `npm uninstall`로 패키지 제거 시 uninstall.sh와 동일한 역할 수행

> ⚠️ **install.sh/uninstall.sh ↔ scripts/postinstall.sh/preuninstall.sh 쌍은 각자 독립 구현이라 함께 수정해야 한다.** curl 원라이너(`install.sh`)는 `check_deps()`에서 jq 부재 시 즉시 종료하지만, npm 훅(`scripts/postinstall.sh`)은 `npm install` 자체를 실패시키지 않기 위해 jq 부재 시 경고만 출력하고 계속 진행한다 — 이 차이는 의도된 것이므로 "동기화"한답시고 없애지 말 것. 두 파일이 완전히 공유 코드를 쓰지 않는 이유는 `install.sh`가 curl로 단일 파일만 받아 실행되는 구조라 별도 lib 파일을 참조할 수 없기 때문(YAGNI로 통합 보류). settings.json 갱신/삭제 로직(jq 커맨드 자체)을 바꿀 때는 4개 파일 모두 확인할 것.

- **.github/workflows/publish.yml**: GitHub Release 발행 시 자동 실행. `verify`(버전 3곳 일치) 잡 이후 `publish-github-packages` 잡이 실행되어 GitHub Packages에 발행한다. npmjs.com 발행(`publish-npmjs` 잡)은 `NPM_TOKEN` 만료로 v1.3.0/v1.3.1/v1.3.3/v1.3.4/v1.5.0에서 반복적으로 실패해 v1.5.0에서 제거함 — GitHub Packages 단일 발행 구조로 전환
- **.github/workflows/ci.yml**: push/PR마다 실행. `shellcheck` 린트 + `tests/`의 `bats` 테스트

### 성능 설계 원칙

- **서브프로세스 최소화**: ~108개 → ~12개 (v1.1.0)
- 색상 코드, progress bar, 토큰 포맷팅 모두 순수 bash (tr, awk 제거)
- jq 호출 통합: 입력 파싱 6→1, 블록 파싱 8→1, 캐시 파싱 4→1
- ccusage cache miss 시 동기 npx 호출 제거, 백그라운드 전용
- `context_window` stdin 필드 사용 시 JSONL 파일 I/O 완전 제거 (v1.3.0)
- 사용되지 않던 `session_txt`/`fmt_time_hm()` 제거로 세션 렌더링 시 불필요한 `date` 서브프로세스 포크 제거 (v1.3.4)

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
- ccusage 없이도 Line 1~2는 정상 동작해야 함 (graceful degradation)
- Git 브랜치명은 dirty(`*`)/ahead-behind(`↑N↓N`) 표시를 포함하며, upstream 미설정 시 ahead/behind는 조용히 생략됨 (graceful degradation과 동일한 원칙)
- context_window stdin 필드를 우선 사용하고, 없을 때만 JSONL fallback

### Usage counter semantics

- Line 3의 `Today` / `Week` / `Month`는 ccusage가 제공하는 **달력 기준** 누적치 (ISO 주, 달력 월). Anthropic의 weekly rate limit은 **rolling 7-day**라 정책 한도 게이지로 직접 환산되지 않음 — 라벨 의미를 바꿀 때는 README의 "Usage Counters" 섹션도 함께 갱신할 것
- Line 2의 `Session`은 ccusage active block 기준 **5시간 rolling window** (2026-05-06 정책 변경 후에도 윈도우 길이는 동일, capacity만 2배)
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
