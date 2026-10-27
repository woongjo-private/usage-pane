import { atom, read, update } from 'claude-code'
import type { Color, EngineInterface, Register, SessionMeasureInput, Timer } from 'claude-code'

import type { Limits, SessionFigures, UsageWindow } from '../types'

const PANE = 'usage-pane'
const TITLE = '사용량'
const COMMAND = 'usage-pane'
const STORE_KEY = 'limits'

const limits = atom({ plugin: 'usage-pane', key: 'limits' } as const, null)
const figures = atom({ plugin: 'usage-pane', key: 'figures' } as const, null)
const now = atom({ plugin: 'usage-pane', key: 'now' } as const, 0)

// 한국어 사용자를 위한 mod 라 리셋 시각은 KST 로 고정해 보여 준다.
const KST_OFFSET_MS = 9 * 60 * 60 * 1000
const DAYS = ['일', '월', '화', '수', '목', '금', '토']
const LABELS: Record<string, string> = {
  five_hour: '5시간 사용량',
  seven_day: '주간 사용량',
  spend_limit: '지출 한도 사용량',
}
// 프롬프트 위 한 줄에 쓰는 짧은 이름
const SHORT_LABELS: Record<string, string> = {
  five_hour: '5시간',
  seven_day: '주간',
  spend_limit: '지출',
}
// 한 줄에 막대까지 들어가는 최소 폭. 좁으면 막대를 뺀다.
const BAND_BAR_MIN_COLUMNS = 64
const BAND_BAR_CELLS = 8
// five_hour → seven_day → 그 밖 순서로 그린다.
const ORDER = ['five_hour', 'seven_day']

type Measured = Pick<SessionMeasureInput, 'context' | 'rateLimits' | 'cost'>

function isLimits(value: unknown): value is Limits {
  const v = value as Limits | null | undefined

  return typeof v?.measuredAt === 'number' && Array.isArray(v.windows)
}

async function refresh($: EngineInterface, u: Measured): Promise<void> {
  const at = await $.clock.now()
  const session: SessionFigures = {
    contextPercent: u.context.percent,
    contextTokens: u.context.tokens,
    contextWindow: u.context.window,
    costUsd: u.cost?.usd,
  }
  await update($, figures, () => session)

  // 한도 수치가 없는 응답(첫 응답 전 등)은 이전 측정값을 지우지 않는다.
  if (u.rateLimits.length > 0) {
    const fresh: Limits = {
      windows: u.rateLimits.map(w => ({ kind: w.kind, percentUsed: w.percentUsed, resetsAt: w.resetsAt })),
      measuredAt: at,
    }
    await update($, limits, () => fresh)
    await $.store.set(STORE_KEY, fresh)
  }
  await update($, now, () => at)
}

// 다른 세션이 더 최근에 측정한 값이 있으면 가져온다.
async function adoptStored($: EngineInterface): Promise<void> {
  const saved = await $.store.get(STORE_KEY)
  if (!isLimits(saved)) return

  await update($, limits, held => (held === null || saved.measuredAt > held.measuredAt ? saved : held))
}

// 리셋 시각이 지난 창은 새 측정 전까지 0% 로 본다.
function usedOf(w: UsageWindow, nowMs: number): number {
  if (w.resetsAt && Date.parse(w.resetsAt) <= nowMs) return 0

  return w.percentUsed
}

function bar(percent: number, cells: number): string {
  const filled = Math.round((Math.min(100, Math.max(0, percent)) / 100) * cells)

  return '█'.repeat(filled) + '░'.repeat(cells - filled)
}

function tone(used: number): Color {
  if (used >= 90) return 'error'
  if (used >= 70) return 'warning'

  return 'success'
}

function pad(n: number): string {
  return String(n).padStart(2, '0')
}

function kst(ms: number): Date {
  return new Date(ms + KST_OFFSET_MS)
}

function clockText(ms: number): string {
  const t = kst(ms)

  return `${pad(t.getUTCHours())}:${pad(t.getUTCMinutes())}`
}

function whenText(ms: number, nowMs: number): string {
  const t = kst(ms)
  const today = kst(nowMs)
  const isToday = t.getUTCFullYear() === today.getUTCFullYear()
    && t.getUTCMonth() === today.getUTCMonth()
    && t.getUTCDate() === today.getUTCDate()

  return isToday ? clockText(ms) : `${t.getUTCMonth() + 1}/${t.getUTCDate()}(${DAYS[t.getUTCDay()]}) ${clockText(ms)}`
}

function spanText(ms: number): string {
  const minutes = Math.ceil(ms / 60_000)
  const d = Math.floor(minutes / 1440)
  const h = Math.floor((minutes % 1440) / 60)
  const m = minutes % 60

  return d > 0 ? `${d}일 ${h}시간` : h > 0 ? `${h}시간 ${m}분` : `${m}분`
}

function detailText(w: UsageWindow, nowMs: number): string {
  const at = w.resetsAt ? Date.parse(w.resetsAt) : Number.NaN
  if (Number.isNaN(at)) return ''
  if (at <= nowMs) return `${whenText(at, nowMs)} 리셋됨 · 다음 응답 뒤 갱신`

  return `${spanText(at - nowMs)} 후 리셋 · ${whenText(at, nowMs)}`
}

function bandResetText(w: UsageWindow, nowMs: number): string {
  const at = w.resetsAt ? Date.parse(w.resetsAt) : Number.NaN
  if (Number.isNaN(at)) return ''
  if (at <= nowMs) return '리셋됨'

  return spanText(at - nowMs)
}

function agoText(measuredAt: number, nowMs: number): string {
  const minutes = Math.floor((nowMs - measuredAt) / 60_000)
  if (minutes < 1) return `${clockText(measuredAt)} 측정`

  return `${clockText(measuredAt)} 측정 (${spanText(minutes * 60_000)} 전)`
}

function sortWindows(windows: UsageWindow[]): UsageWindow[] {
  const rank = (kind: string) => {
    const i = ORDER.indexOf(kind)

    return i === -1 ? ORDER.length : i
  }

  return [...windows].sort((a, b) => rank(a.kind) - rank(b.kind))
}

function tokensText(tokens: number): string {
  return tokens >= 1000 ? `${Math.round(tokens / 1000)}k` : String(tokens)
}

function contextText(session: SessionFigures): string {
  const percent = session.contextPercent === undefined ? '—' : `${session.contextPercent}%`
  if (session.contextTokens === undefined) return `컨텍스트 ${percent}`

  return `컨텍스트 ${percent} · ${tokensText(session.contextTokens)} / ${tokensText(session.contextWindow)} 토큰`
}

export const register: Register = on => {
  let ticker: Timer | undefined

  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: COMMAND,
      description: '5시간·주간 사용량 패널을 연다',
    })
    await refresh($, await $.session.usage())
    await adoptStored($)

    // 1분마다 남은 시간을 줄이고, 다른 세션이 남긴 더 새 측정값을 가져온다.
    ticker?.cancel()
    ticker = $.clock.every(60_000, () => {
      void adoptStored($)
        .then(() => $.clock.now())
        .then(t => update($, now, () => t))
    })

    // 우측 패널은 자리를 많이 차지해 자동으로 열지 않는다. 늘 보이는 건 프롬프트 위 한 줄이다.
    return next(e)
  })

  on('session.measure', async ($, e, next) => {
    await refresh($, e)

    return next(e)
  })

  on('session.end', ($, e, next) => {
    ticker?.cancel()
    ticker = undefined

    return next(e)
  })

  on('command.run', { command: COMMAND }, async $ => {
    await refresh($, await $.session.usage())
    await adoptStored($)
    const { isPlaced } = await $.ui.open({ id: PANE, title: TITLE })

    return { text: isPlaced ? '사용량 패널을 열었습니다.' : '패널을 그릴 화면이 없어 아직 보이지 않습니다.' }
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)

    const held = await read($, limits)
    if (held === null || held.windows.length === 0) return next(e)

    const { Box, Text } = $.ui.resolve(e)
    const nowMs = await read($, now)
    const withBars = e.props.bodyColumns >= BAND_BAR_MIN_COLUMNS

    return (
      <Box flexDirection="row" flexWrap="wrap" columnGap={1}>
        {sortWindows(held.windows).map((w, i) => {
          const used = usedOf(w, nowMs)
          const reset = bandResetText(w, nowMs)

          return (
            <Box key={w.kind} flexDirection="row" columnGap={1}>
              {i > 0 && <Text dimColor>·</Text>}
              <Text dimColor>{SHORT_LABELS[w.kind] ?? w.kind}</Text>
              <Text color={tone(used)} bold>{used}%</Text>
              {withBars && <Text color={tone(used)} mono>{bar(used, BAND_BAR_CELLS)}</Text>}
              {reset !== '' && <Text dimColor>{reset}</Text>}
            </Box>
          )
        })}
      </Box>
    )
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const held = await read($, limits)
    const session = await read($, figures)
    const nowMs = await read($, now)
    const cells = Math.max(10, Math.min(36, e.props.bodyColumns - 2))
    const windows = held === null ? [] : sortWindows(held.windows)

    return (
      <Box flexDirection="column" gap={1}>
        {windows.length === 0 && (
          <Text dimColor wrap="wrap">
            아직 측정한 한도 값이 없습니다. 응답이 한 번 오면 표시됩니다. 구독(Pro·Max·Team) 계정에서만 제공됩니다.
          </Text>
        )}
        {windows.map(w => {
          const used = usedOf(w, nowMs)
          const detail = detailText(w, nowMs)

          return (
            <Box key={w.kind} flexDirection="column">
              <Box flexDirection="row" justifyContent="space-between">
                <Text weight="semibold">{LABELS[w.kind] ?? w.kind}</Text>
                <Text color={tone(used)} weight="bold" size="heading" tabular>{used}%</Text>
              </Box>
              <Text color={tone(used)} mono>{bar(used, cells)}</Text>
              {detail !== '' && <Text dimColor size="footnote" wrap="wrap">{detail}</Text>}
            </Box>
          )
        })}
        {held !== null && windows.length > 0 && (
          <Text dimColor size="caption">{agoText(held.measuredAt, nowMs)}</Text>
        )}
        {session !== null && (
          <Box flexDirection="column">
            <Text dimColor size="footnote">{contextText(session)}</Text>
            {session.costUsd !== undefined && (
              <Text dimColor size="footnote">이 세션 비용(API 환산) ${session.costUsd.toFixed(2)}</Text>
            )}
          </Box>
        )}
      </Box>
    )
  })
}
