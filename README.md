# usage-pane

Claude Code 의 5시간·주간 사용 한도를 프롬프트 바로 위 한 줄에 늘 보여 주는 mod.

```
5시간 37% ███░░░░░ 2시간 30분 · 주간 71.5% ██████░░ 2일 21시간
```

- 사용 % 와 막대, 리셋까지 남은 시간을 보여 준다. 70% 이상은 경고색, 90% 이상은 빨간색.
- 창이 좁으면 막대를 빼고 숫자와 남은 시간만 보여 준다.
- `/usage-pane` 으로 우측 패널을 열면 리셋 시각, 컨텍스트, 이 세션 비용(API 환산)까지 보인다.

## 설치

터미널의 Claude Code 프롬프트에서:

```
/plugin install usage-pane --marketplace woongjo-private/usage-pane
```

셸에서:

```bash
claude plugin install usage-pane --marketplace woongjo-private/usage-pane
```

`Add marketplace?` 에는 `y`, 범위는 user 를 고르면 이후 모든 세션에서 동작한다.

데스크톱 앱 Code 탭에서는 `/plugin` 이 동작하지 않는다. 프롬프트 입력창 옆 + → Plugins → Add marketplace 에 `woongjo-private/usage-pane` 을 넣고 Add plugin 을 누른다.
터미널에서 user 범위로 설치한 mod 는 데스크톱 앱 Code 탭 세션에서도 동작한다.

## 갱신 주기

- 사용 % 는 Claude API 응답에 실려 오는 값이다. 턴이 끝날 때마다, 그리고 턴 중에도 1%p 이상 움직이면 갱신된다. 응답이 없으면 바뀌지 않는다.
- 마지막 측정값을 저장해 두어 새 세션도 첫 응답 전에 바로 보여 준다. 다른 세션이 더 최근에 잰 값은 1분마다 가져온다.
- 리셋까지 남은 시간은 1분마다 줄어든다. 리셋 시각이 지나면 0% 로 바뀐다.
- claude.ai 웹·모바일에서 쓴 양은 이 컴퓨터의 Claude Code 세션이 다음 응답을 받을 때 반영된다.

## 알아 둘 것

- 한도는 구독(Pro·Max·Team) 계정에서만 제공된다. 측정값이 없으면 한 줄을 그리지 않는다.
- 리셋 시각은 KST(UTC+9) 기준으로 보여 준다.
- Claude Code 2.1.308 에서 만들고 확인했다. mod(function hooks) 를 지원하지 않는 이전 버전에서는 동작하지 않는다.

## 채팅에서도 보기 — 메뉴 막대 앱 (`menubar/`)

usage-pane 은 Claude Code 안에서만 동작한다. 데스크톱 앱 Chat 탭이나 claude.ai 웹에서 채팅할 때도 한도를 보려면
메뉴 막대 앱 UsageBar 를 쓴다. Claude와 Codex의 사용량을 각각 한 줄씩, 총 두 줄로 표시한다.
각 숫자는 **남은 비율이 아니라 사용한 비율**이다.
메뉴 막대와 상세 메뉴의 사용 비율은 정수로 반올림해 표시한다. 5시간 영역은 `100%`가 들어가는 폭으로 고정해 두 줄의 `주간` 시작 위치를 맞춘다.

```
Claude  5시간 29% · 주간 44%
Codex   5시간 12% · 주간 35%
```

```bash
./menubar/build.sh
open menubar/build/UsageBar.app
```

- Xcode Command Line Tools 의 `swiftc` 만 쓴다. 따로 설치할 것은 없다.
- 로그인할 때 켜려면 시스템 설정 → 일반 → 로그인 항목 → + 에서 `UsageBar.app` 을 추가한다.
- 메뉴를 열면 Claude Code와 Codex 각각의 사용 %·리셋 시각·측정 시각이 보인다. 70% 이상은 주황, 90% 이상은 빨강이다.
- 측정한 지 15분이 지나면 해당 줄을 흐리게 그린다. Codex 조회 실패 시 이전 값이 있으면 흐리게 유지하고 `!`를 붙인다. 오류 내용은 메뉴에서 확인한다.
- 계정에서 제공하지 않는 창이나 아직 확인하지 못한 값은 `—`로 표시한다. 예를 들어 Codex가 주간 한도만 제공하면 `5시간 — · 주간 4%`가 정상이다.
- `UsageBar --once` 는 메뉴 막대 없이 한 번 읽어 메뉴 막대 글자와 메뉴 내용을 출력한다.
- `./menubar/test.sh` 는 저장값·글자·주기·Codex 창 구분과 가짜 CLI를 이용한 초기화/조회/오류/시간 초과를 확인한다. `--preview`를 붙이면 두 줄의 밝은/어두운 테마 미리보기도 `menubar/build/`에 저장한다.

### 갱신 주기

- 메뉴 → 갱신 주기에서 1·3·5·10·30분 중에 고르거나, "직접 입력…"에 분 단위 정수(1~1440)를 넣는다. 기본은 1분이다.
- 바꾸면 바로 한 번 갱신하고 그때부터 새 주기로 세며, 다음 실행에도 유지된다. 메뉴를 열 때와 잠자기에서 깰 때도 갱신한다.
- 셸에서는 `defaults write io.github.woongjo-private.usage-bar refreshMinutes -int <분>` 으로 주고 앱을 다시 켠다.
- Claude는 저장 파일을 다시 읽고, Codex는 백그라운드에서 사용량만 조회한다. Codex 조회가 늦거나 실패해도 메뉴 막대와 Claude 표시는 계속 동작한다.

### Claude 수치 출처

- usage-pane 이 남기는 마지막 측정값(`~/.claude/plugins/store/usage-pane_*.json`)을 읽는다. 이 값은 Claude Code 세션이
  응답을 받을 때마다 바뀐다. 그래서 **채팅에서만 쓴 양은 다음에 Claude Code 세션이 응답을 받을 때 반영된다.**
- Claude Code `/usage` 가 쓰는 `GET https://api.anthropic.com/api/oauth/usage` 를 직접 조회하면 채팅 사용량도 바로
  반영되지만 넣지 않았다. 키체인의 CLI 로그인 토큰(`Claude Code-credentials`)이 필요한데, 데스크톱 앱만 쓰면 이 토큰이
  만료된 채로 남는다 (2026-10-29 확인: `expiresAt` 0, API 401). 토큰을 앱이 대신 갱신하지 않기로 했고, 이 조회는 쓰지 않기로 결정했다.

### Codex 수치 출처

- 기존 Codex 로그인을 이용해 `codex app-server`의 [`account/rateLimits/read`](https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt)를 호출한다. API 키를 추가하거나 인증 파일/키체인 토큰을 직접 읽지 않는다.
- `initialize` → `initialized` → `account/rateLimits/read`만 사용한다. 새 채팅이나 AI 요청을 만들지 않으며, 조회 뒤 서버를 종료한다. 조회 제한 시간은 15초다.
- ChatGPT/Codex 앱에 포함된 CLI, PATH, Homebrew 설치 경로를 찾는다. 별도 경로가 필요하면 실행 환경에 `CODEX_CLI_PATH=/절대/경로/codex`를 지정할 수 있다.
- `rateLimitsByLimitId.codex`를 우선하고 구버전의 `rateLimits`도 지원한다. 창의 길이가 300분이면 5시간, 10080분이면 주간으로 표시한다. `primary`가 주간일 수 있으므로 위치로 추측하지 않는다.
- 없는 창을 0%나 무제한으로 해석하지 않는다. 리셋 시각이 지난 Codex 값은 새 조회 전까지 `—`로 표시한다.
- 로그인·네트워크 오류는 메뉴에서 안내한다. 별도 계정으로 로그인한 CLI를 지정하면 그 계정의 사용량이 표시되므로 데스크톱 앱과 같은 계정인지 확인한다.

### Codex 입력창 위 표시

Claude mod의 `ui.render / AbovePrompt`는 Claude 전용이다. GPT 앱의 Codex 플러그인에는 현재 같은 위치에 UI를 삽입하는 공개 훅이 확인되지 않았다.
공식 [Plugin Extensions](https://developers.openai.com/plugins/build/extensions)는 대화 옆 패널 등을 제공한다. 메뉴 막대 표시는 Codex의 새 채팅에서도 계속 볼 수 있다.
