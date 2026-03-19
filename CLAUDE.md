# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Claude Code CLI용 3줄 컴팩트 statusline 스크립트. 세션 컨텍스트 사용량, 토큰/비용 통계, Git 정보를 터미널에 실시간 표시한다. 순수 Bash 스크립트로 빌드/테스트/린트 도구 없음.

## Development

빌드/테스트/린트 도구 없음. 수동 테스트로 검증한다.

```bash
# 로컬 테스트 (mock stdin으로 statusline 실행)
echo '{"workspace":{"current_dir":"/tmp/test"},"model":{"display_name":"Opus 4.6"},"session_id":"test-123","version":"1.0.44","output_style":{"name":"explanatory"}}' | bash statusline.sh

# NO_COLOR 모드 테스트
echo '{}' | NO_COLOR=1 bash statusline.sh

# 실제 Claude Code에 연결해서 테스트 (statusline.sh를 ~/.claude/에 복사 후 재시작)
cp statusline.sh ~/.claude/statusline.sh
```

## Architecture

### 핵심 흐름

```
Claude Code CLI → stdin(세션 JSON) → statusline.sh → stdout(3줄 ANSI 출력)
```

`statusline.sh`는 Claude Code가 매 렌더링마다 호출하며, 4개 데이터 소스를 조합한다:

| 소스 | 위치 | 출력 라인 |
|------|------|-----------|
| stdin JSON | Claude Code가 전달 | Line 1 (dir, model, version, style) |
| 세션 JSONL | `~/.claude/projects/-{encoded-dir}/{session-id}.jsonl` 마지막 20줄 | Line 2 (컨텍스트 토큰) |
| ccusage 캐시 | `~/.claude/stats-cache.json` (TTL 60초, 백그라운드 갱신) | Line 2 (세션), Line 3 (비용) |
| Git | `git branch --show-current` | Line 1 (브랜치명) |

### stdin JSON 스키마

Claude Code가 전달하는 입력. `jq`로 한 번에 파싱하며 Unit Separator(`\u001f`)로 분리:

```json
{
  "workspace": { "current_dir": "/Users/..." },
  "model": { "display_name": "Opus 4.6" },
  "session_id": "uuid-string",
  "version": "1.0.44",
  "output_style": { "name": "explanatory" }
}
```

### statusline.sh 내부 구조

| 영역 | 줄 범위 | 역할 |
|------|---------|------|
| 색상 변수 | ~27-48 | `NO_COLOR` 대응, 서브셸 없이 ANSI 코드 사전 계산 |
| 헬퍼 함수 | ~50-104 | `to_epoch()`, `progress_bar()`, `format_tokens()` 등 순수 bash 구현 |
| 캐싱 레이어 | ~106-187 | ccusage 결과 캐시, 4개 명령 병렬 실행으로 백그라운드 갱신 |
| 입력 파싱 | ~189-209 | 단일 jq 호출, Unit Separator(0x1f) 구분자 |
| 컨텍스트 계산 | ~217-263 | 모델별 컨텍스트 윈도우 매핑, 사용률 기반 동적 색상 |
| ccusage 통합 | ~265-353 | 일/주/월 통계, 세션 시간, 캐시 히트율 |
| 렌더링 | ~365-467 | 3줄 출력 조립 |

### 파일 역할

- **statusline.sh**: 메인 스크립트. `~/.claude/settings.json`에 `"statusline": "~/.claude/statusline.sh"` 형태로 등록
- **install.sh**: 원라이너 설치 (`curl | bash`). 의존성 확인 → GitHub에서 다운로드 → settings.json에 statusline 필드 추가. 기존 settings.json이 있으면 `.backup` 생성
- **uninstall.sh**: `~/.claude/statusline.sh`와 `~/.claude/stats-cache.json` 삭제, settings.json에서 statusline 필드 제거
- **scripts/postinstall.sh**: npm `postinstall` 훅. `npm install`로 패키지 설치 시 install.sh와 동일한 역할 수행 (statusline.sh 복사 + settings.json 등록)
- **scripts/preuninstall.sh**: npm `preuninstall` 훅. `npm uninstall`로 패키지 제거 시 uninstall.sh와 동일한 역할 수행

### 성능 설계 원칙

- **서브프로세스 최소화**: ~108개 → ~12개 (v1.1.0)
- 색상 코드, progress bar, 토큰 포맷팅 모두 순수 bash (tr, awk 제거)
- jq 호출 통합: 입력 파싱 6→1, 블록 파싱 8→1, 캐시 파싱 4→1
- ccusage cache miss 시 동기 npx 호출 제거, 백그라운드 전용

## Dependencies

- **필수**: `jq`
- **권장**: `ccusage` (없으면 Line 3 비용 통계 생략, graceful degradation)
- **선택**: `gdate` (macOS coreutils, 없으면 BSD date 또는 Python3 fallback)

## Key Conventions

- 모든 jq 호출은 최소 횟수로 통합 (성능상 단일 호출 선호)
- 필드 구분자로 Unit Separator(`\u001f`) 사용 (탭/공백과 충돌 방지)
- 동적 색상 임계값: 컨텍스트 잔여 ≤20% 빨강, ≤40% 노랑, >40% 초록
- `NO_COLOR` 환경변수 지원 필수
- ccusage 없이도 Line 1~2는 정상 동작해야 함 (graceful degradation)

## Versioning & Release

- 버전은 `statusline.sh` 헤더의 `# Version: X.Y.Z` 에서 단일 관리
- Annotated 태그 사용: `git tag -a vX.Y.Z -m "메시지"`
- 릴리즈 생성: `gh release create vX.Y.Z --title "vX.Y.Z" --notes "..."`
- 릴리즈 노트 구성: 프로젝트 소개 1줄, Features, Installation one-liner, Changes since 이전 버전, Requirements
- install.sh URL은 `main` 브랜치 고정 (태그별 URL 아님)
- `package.json` 버전은 `statusline.sh` 헤더와 반드시 동기화
- GitHub Release 생성 시 `.github/workflows/publish.yml`이 GitHub Packages에 자동 발행
- 릴리즈 전 3곳 버전 일치 확인 필수: `statusline.sh` 헤더, `package.json`, git 태그 (CI가 자동 검증하므로 불일치 시 publish 실패)
