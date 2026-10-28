// Live Activity: the spinner says how much this turn has done so far, and the
// status line keeps a summary of the last turn once it ends.
//
//   Thinking · 7 tools · 2 agents…
//   last turn 1m 04s · 12 tools · 2 agents · 48k in / 3.1k out
//
// Claude Code's own spinner already shows elapsed time and output tokens, so
// this adds what it leaves out: tool calls (main thread and subagents) and
// subagents started.

import type { Register } from 'claude-code'

let tools = 0
let subTools = 0
let agents = 0

function short(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`
  if (n >= 1_000) return `${(n / 1_000).toFixed(n >= 10_000 ? 0 : 1)}k`
  return String(n)
}

function duration(ms: number): string {
  const s = Math.round(ms / 1000)
  if (s < 60) return `${s}s`
  return `${Math.floor(s / 60)}m ${String(s % 60).padStart(2, '0')}s`
}

function plural(n: number, word: string): string {
  return `${n} ${word}${n === 1 ? '' : 's'}`
}

export const register: Register = on => {
  on('turn.start', ($, e, next) => {
    if (!e.agentId) {
      tools = 0
      subTools = 0
      agents = 0
    }
    return next(e)
  })

  on('tool.call', ($, e, next) => {
    if (e.agentId) subTools += 1
    else tools += 1
    if (e.tool === 'Agent') agents += 1
    $.ui.invalidate('ui.render')
    return next(e)
  })

  on('ui.render', { component: 'Spinner' }, ($, e, next) => {
    if (tools + subTools === 0) return next(e)
    const parts = [` · ${plural(tools + subTools, 'tool')}`]
    if (agents) parts.push(plural(agents, 'agent'))
    return next({ ...e, props: { ...e.props, suffix: parts.join(' · ') + '…' } })
  })

  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    if (e.agentId) return result
    const parts = [`last turn ${duration(e.durationMs)}`, plural(tools + subTools, 'tool')]
    if (agents) parts.push(plural(agents, 'agent'))
    if (e.usage) {
      const u = e.usage
      const input = u.input_tokens + (u.cache_read_input_tokens ?? 0) + (u.cache_creation_input_tokens ?? 0)
      parts.push(`${short(input)} in / ${short(u.output_tokens)} out`)
    }
    $.ui.status(parts.join(' · '))
    return result
  })
}
