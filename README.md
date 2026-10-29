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
메뉴 막대 앱 UsageBar 를 쓴다. 채팅에서 쓴 양도 같은 한도에 잡힌다.

```
5시간 29% · 주간 44%
```

```bash
./menubar/build.sh
open menubar/build/UsageBar.app
```

- Xcode Command Line Tools 의 `swiftc` 만 쓴다. 따로 설치할 것은 없다.
- 로그인할 때 켜려면 시스템 설정 → 일반 → 로그인 항목 → + 에서 `UsageBar.app` 을 추가한다.
- 메뉴를 열면 창별 사용 %·리셋 시각과 측정 시각이 보인다. 70% 이상은 주황, 90% 이상은 빨강이다.
- 측정한 지 15분이 지나면 메뉴 막대 글자를 흐리게 그린다.
- `UsageBar --once` 는 메뉴 막대 없이 한 번 읽어 메뉴 막대 글자와 메뉴 내용을 출력한다.
- `./menubar/test.sh` 는 저장값 읽기·글자 만들기·주기 입력 같은 순수 함수를 확인한다.

### 수치 출처와 갱신 주기

- usage-pane 이 남기는 마지막 측정값(`~/.claude/plugins/store/usage-pane_*.json`)을 읽는다. 이 값은 Claude Code 세션이
  응답을 받을 때마다 바뀐다. 그래서 **채팅에서만 쓴 양은 다음에 Claude Code 세션이 응답을 받을 때 반영된다.**
- 갱신 주기는 이 파일을 다시 읽는 주기다. 메뉴 → 갱신 주기에서 1·3·5·10·30분 중에 고르거나, "직접 입력…" 에
  분 단위 정수(1~1440)를 넣는다. 기본은 1분이다(usage-pane 이 다른 세션의 측정값을 가져오는 주기와 같다).
  바꾸면 바로 한 번 읽고 그때부터 새 주기로 세며, 다음 실행에도 유지된다. 메뉴를 열 때와 잠자기에서 깰 때도 읽는다.
- 셸에서는 `defaults write io.github.woongjo-private.usage-bar refreshMinutes -int <분>` 으로 주고 앱을 다시 켠다.
- Claude Code `/usage` 가 쓰는 `GET https://api.anthropic.com/api/oauth/usage` 를 직접 조회하면 채팅 사용량도 바로
  반영되지만 넣지 않았다. 키체인의 CLI 로그인 토큰(`Claude Code-credentials`)이 필요한데, 데스크톱 앱만 쓰면 이 토큰이
  만료된 채로 남는다 (2026-10-29 확인: `expiresAt` 0, API 401). 토큰을 앱이 대신 갱신하지 않기로 했고, 이 조회는 쓰지 않기로 결정했다.
