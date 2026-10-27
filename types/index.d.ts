export type UsageWindow = { kind: string; percentUsed: number; resetsAt?: string }

// 한도는 계정 단위라 세션을 넘어 $.store 에도 남긴다.
export type Limits = { windows: UsageWindow[]; measuredAt: number }

export type SessionFigures = {
  contextPercent?: number
  contextTokens?: number
  contextWindow: number
  costUsd?: number
}

declare module 'claude-code' {
  interface PluginState {
    'usage-pane': { limits: Limits | null; figures: SessionFigures | null; now: number }
  }
}
