import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

// 2026-10-27 12:00 KST
const NOW = Date.parse('2026-10-27T03:00:00Z')

const FIVE_HOUR = { kind: 'five_hour', percentUsed: 37, resetsAt: '2026-10-27T05:30:00Z' }
const SEVEN_DAY = { kind: 'seven_day', percentUsed: 71.5, resetsAt: '2026-10-30T00:00:00Z' }

const USAGE = {
  startedAt: NOW,
  context: { tokens: 84_000, window: 200_000, percent: 42 },
  rateLimits: [SEVEN_DAY, FIVE_HOUR],
  cost: { usd: 1.234 },
}

const PANE = {
  plugin: 'usage-pane',
  component: 'Pane',
  requestId: 'usage-pane',
  props: {
    title: '사용량',
    isFocused: false,
    bodyColumns: 40,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 30 },
    view: {},
  },
} as const

const BAND = {
  plugin: 'usage-pane',
  component: 'AbovePrompt',
  props: {
    hasSurvey: false,
    isWorking: false,
    maxRows: 10,
    bodyColumns: 100,
    scroll: { offset: 0, bodyRows: 10 },
    view: {},
  },
} as const

// 세션이 공유하는 $.store 를 흉내 낸다: 다른 세션의 쓰기를 test 가 직접 넣는다.
function sharedStore(on: On, initial?: unknown) {
  const box = { saved: initial }
  on('store.get', () => ({ value: box.saved }))
  on('store.set', (_, e) => {
    box.saved = e.value

    return { value: undefined }
  })

  return box
}

// 엔진 대역: 패널을 연 id 를 돌려준다.
function engine(on: On, usage: typeof USAGE) {
  const opened: string[] = []
  on('command.register', () => ({ value: { command: 'usage-pane' } }))
  on('ui.open', (_, e) => {
    opened.push(e.id)

    return { value: { isPlaced: true } }
  })
  on('session.usage', () => ({ value: usage }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.measure', (_, e) => ({ changed: e.changed }))

  return opened
}

test('5시간·주간 사용량과 리셋까지 남은 시간을 그린다', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const store = sharedStore(on)
  engine(on, USAGE)

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })

  for (const surface of ['terminal', 'desktop', 'vscode', 'mobile'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect((await ui.find({ type: 'Text', text: /^5시간 사용량$/ }))?.text).toBe('5시간 사용량')
    expect((await ui.find({ type: 'Text', text: /^37%$/ }))?.text).toBe('37%')
    expect((await ui.find({ type: 'Text', text: /^71.5%$/ }))?.text).toBe('71.5%')
    expect((await ui.find({ type: 'Text', text: /14:30$/ }))?.text).toBe('2시간 30분 후 리셋 · 14:30')
    expect((await ui.find({ type: 'Text', text: /09:00$/ }))?.text).toBe('2일 21시간 후 리셋 · 10/30(금) 09:00')
    expect((await ui.find({ type: 'Text', text: /^컨텍스트/ }))?.text).toBe('컨텍스트 42% · 84k / 200k 토큰')
    expect((await ui.find({ type: 'Text', text: /비용/ }))?.text).toBe('이 세션 비용(API 환산) $1.23')
    await ui.unmount()
  }
  expect(store.saved).toEqual({ windows: [SEVEN_DAY, FIVE_HOUR], measuredAt: NOW })

  // 1분 지나면 남은 시간이 줄어든다.
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  await clock.advance(60_000)
  expect((await ui.find({ type: 'Text', text: /14:30$/ }))?.text).toBe('2시간 29분 후 리셋 · 14:30')
  expect((await ui.find({ type: 'Text', text: /측정/ }))?.text).toBe('12:00 측정 (1분 전)')
  await ui.unmount()
})

test('세션이 시작해도 우측 패널은 열지 않고, 명령으로만 연다', async ($, on) => {
  mock.clock(on, { now: NOW })
  sharedStore(on)
  const opened = engine(on, USAGE)

  await $.session.start({ cwd: '/', surface: null, isInteractive: false })
  expect(opened).toEqual([])

  await $.command.run({
    command: 'usage-pane',
    args: '',
    origin: { kind: 'sdk' },
    presentation: { isFullscreen: false, columns: 80 },
  })
  expect(opened).toEqual(['usage-pane'])
})

test('프롬프트 위 한 줄에 5시간·주간 사용량과 리셋까지 남은 시간을 그린다', async ($, on) => {
  mock.clock(on, { now: NOW })
  sharedStore(on)
  engine(on, USAGE)

  await $.session.start({ cwd: '/', surface: null, isInteractive: false })

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...BAND, surface })
    expect((await ui.find({ type: 'Text', text: /^5시간$/ }))?.text).toBe('5시간')
    expect((await ui.find({ type: 'Text', text: /^37%$/ }))?.text).toBe('37%')
    expect((await ui.find({ type: 'Text', text: /^2시간 30분$/ }))?.text).toBe('2시간 30분')
    expect((await ui.find({ type: 'Text', text: /^주간$/ }))?.text).toBe('주간')
    expect((await ui.find({ type: 'Text', text: /^71.5%$/ }))?.text).toBe('71.5%')
    expect((await ui.find({ type: 'Text', text: /^2일 21시간$/ }))?.text).toBe('2일 21시간')
    expect((await ui.find({ type: 'Text', text: /^█{3}░{5}$/ }))?.text).toBe('███░░░░░')
    await ui.unmount()
  }

  // 좁으면 막대를 뺀다.
  const narrow = await $.ui.mount({ ...BAND, props: { ...BAND.props, bodyColumns: 40 }, surface: 'desktop' })
  expect((await narrow.find({ type: 'Text', text: /^37%$/ }))?.text).toBe('37%')
  expect(await narrow.find({ type: 'Text', text: /█|░/ })).toBeUndefined()
  await narrow.unmount()
})

test('측정값이 없거나 설문이 떠 있으면 한 줄을 비켜 준다', async ($, on) => {
  mock.clock(on, { now: NOW })
  sharedStore(on)
  engine(on, { ...USAGE, rateLimits: [] })
  on('ui.render', { component: 'AbovePrompt' }, ($, e) => {
    const { Text } = $.ui.resolve(e)

    return <Text>engine</Text>
  })

  await $.session.start({ cwd: '/', surface: null, isInteractive: false })
  const empty = await $.ui.mount({ ...BAND, surface: 'desktop' })
  expect((await empty.find({ type: 'Text', text: /engine/ }))?.text).toBe('engine')
  await empty.unmount()

  await $.session.measure({
    context: USAGE.context,
    rateLimits: [FIVE_HOUR],
    cost: USAGE.cost,
    changed: ['rateLimits'],
  })
  const survey = await $.ui.mount({ ...BAND, props: { ...BAND.props, hasSurvey: true }, surface: 'desktop' })
  expect((await survey.find({ type: 'Text', text: /engine/ }))?.text).toBe('engine')
  expect(await survey.find({ type: 'Text', text: /^37%$/ })).toBeUndefined()
  await survey.unmount()
})

test('새 세션은 첫 응답 전에도 마지막 측정값을 보여 준다', async ($, on) => {
  mock.clock(on, { now: NOW })
  sharedStore(on, { windows: [FIVE_HOUR, SEVEN_DAY], measuredAt: NOW - 30 * 60_000 })
  engine(on, { ...USAGE, rateLimits: [] })

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /^37%$/ }))?.text).toBe('37%')
  expect((await ui.find({ type: 'Text', text: /측정/ }))?.text).toBe('11:30 측정 (30분 전)')
  await ui.unmount()
})

test('응답이 알려 준 새 수치와 다른 세션의 더 새 측정값으로 다시 그린다', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const store = sharedStore(on)
  engine(on, { ...USAGE, rateLimits: [] })

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect(await ui.find({ type: 'Text', text: /아직 측정한/ })).toBeDefined()

  await $.session.measure({
    context: USAGE.context,
    rateLimits: [{ ...FIVE_HOUR, percentUsed: 93 }],
    cost: USAGE.cost,
    changed: ['rateLimits'],
  })
  expect((await ui.find({ type: 'Text', text: /^93%$/ }))?.text).toBe('93%')

  // 다른 세션이 2분 뒤에 측정해 남긴 값
  store.saved = { windows: [{ ...FIVE_HOUR, percentUsed: 96 }], measuredAt: NOW + 2 * 60_000 }
  await clock.advance(3 * 60_000)
  expect((await ui.find({ type: 'Text', text: /^96%$/ }))?.text).toBe('96%')
  await ui.unmount()
})

test('리셋 시각이 지나면 0% 로 보여 준다', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  sharedStore(on)
  engine(on, USAGE)

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  await clock.set(Date.parse('2026-10-27T05:31:00Z'))
  expect((await ui.find({ type: 'Text', text: /^0%$/ }))?.text).toBe('0%')
  expect((await ui.find({ type: 'Text', text: /리셋됨/ }))?.text).toBe('14:30 리셋됨 · 다음 응답 뒤 갱신')
  await ui.unmount()
})
