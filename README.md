# claude-statusline

[![GitHub Release](https://img.shields.io/github/v/release/ahngbeom/claude-statusline)](https://github.com/Ahngbeom/claude-statusline/releases)

A detailed, informative statusline for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI.

Claude Code CLI를 위한 상세한 상태 표시줄입니다.

---

## Features / 기능

Display comprehensive session information in your Claude Code terminal:

Claude Code 터미널에 다양한 세션 정보를 표시합니다:

| Line | Content / 내용 |
|------|----------------|
| 1 | 📂 Directory + Git branch │ Model, CLI version, Output style │ 💻 Memory |
| 2 | 🧠 Context usage (bar) │ Session time + tokens + cost │ 🗄 Cache + Speed |
| 3 | 💰 Today │ Week │ Month usage & costs |

### Example Output / 예시 출력

```
📂 ~/projects/myapp  main │ Opus 4.6  v1.0.44  explanatory  │ 💻 Mem 42%
🧠 Context 45.2K/200K [============--------] 77% │ Session 1.2M $0.12  3h 42m [====------] │ 🗄 87%  12.5K/m
💰 Today 2.1M  $4.32 │ Week 15.8M  $31.20 │ Month 48.2M  $95.50
```

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

1. Download statusline.sh / statusline.sh 다운로드:
```bash
curl -fsSL https://raw.githubusercontent.com/ahngbeom/claude-statusline/main/statusline.sh \
  -o ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
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

## Customization / 커스터마이징

Edit `~/.claude/statusline.sh` to customize:

`~/.claude/statusline.sh`를 편집하여 커스터마이징:

### Environment Variables / 환경 변수

| Variable | Effect |
|----------|--------|
| `NO_COLOR=1` | Disable ANSI colors / 색상 비활성화 |
| `STATUSLINE_UNICODE=1` | Use `▰▱` block chars instead of `=-` (may misalign in some terminals) |

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
