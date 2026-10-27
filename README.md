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
