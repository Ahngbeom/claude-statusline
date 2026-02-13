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
| 1 | 📂 Directory + Git branch │ Model, CLI version, Output style |
| 2 | 🧠 Context usage (▰▱ bar) │ Session time + tokens │ 🗄 Cache + Speed |
| 3 | 💰 Today │ Week │ Month usage & costs |

### Example Output / 예시 출력

```
📂 ~/projects/myapp  main │ Opus 4.6  v1.0.44  explanatory
🧠 Context 45.2K/200K ▰▰▰▰▰▰▰▰▰▰▰▰▱▱▱▱▱▱▱▱ 77% │ Session 1.2M  3h 42m ▰▰▰▰▱▱▱▱▱▱ │ 🗄 87%  12.5K/m
💰 Today 2.1M  $4.32 │ Week 15.8M  $31.20 │ Month 48.2M  $95.50
```

Graceful degradation (without ccusage / ccusage 없이):
```
📂 ~/projects/myapp  main │ Opus 4.6  v1.0.44  explanatory
🧠 Context 45.2K/200K ▰▰▰▰▰▰▰▰▰▰▰▰▱▱▱▱▱▱▱▱ 77%
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

---

## Customization / 커스터마이징

Edit `~/.claude/statusline.sh` to customize:

`~/.claude/statusline.sh`를 편집하여 커스터마이징:

### Disable Colors / 색상 비활성화

Set environment variable / 환경 변수 설정:
```bash
export NO_COLOR=1
```

### Modify Progress Bar Width / 프로그레스 바 너비 수정

The progress bar uses `▰` (filled) and `▱` (empty) characters. Find calls to `progress_bar` and change the width:

프로그레스 바는 `▰` (채움)과 `▱` (빈칸) 문자를 사용합니다:
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

1. **Context Calculation**: Reads session JSONL files to calculate token usage
2. **Usage Statistics**: Integrates with [ccusage](https://github.com/anthropics/ccusage) for detailed metrics
3. **Caching**: Background caching prevents UI delays (60s TTL)
4. **Model Detection**: Automatically detects context window size based on model

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

### Context showing "TBD" / 컨텍스트가 "TBD"로 표시됨

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
