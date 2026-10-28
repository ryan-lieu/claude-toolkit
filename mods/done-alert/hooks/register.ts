// Done Alert: tells you when to look back at Claude Code.
//   - a turn that ran at least the threshold (default 30 s) finished -> notification + chime
//   - Claude is waiting on a permission prompt or asked you a question -> notification + a different chime
// Short turns stay quiet, so working in the window isn't noisy.
//
// /alerts                 current settings
// /alerts off | on        all alerts
// /alerts sound off | on  chimes only
// /alerts after 60        seconds a turn must run before "done" alerts

import type { EngineInterface, Register } from 'claude-code'

type Settings = { isOn: boolean; hasSound: boolean; afterSeconds: number }
const DEFAULTS: Settings = { isOn: true, hasSound: true, afterSeconds: 30 }
let settings: Settings = { ...DEFAULTS }
let lastAskAt = 0

function firstLine(text: string): string {
  const line = text.split('\n').find(l => l.trim() !== '') ?? ''
  return line.length > 90 ? line.slice(0, 89) + '…' : line
}

async function alert($: EngineInterface, text: string, sound: string) {
  if (!settings.isOn) return
  try {
    await $.ui.notify(text, { title: 'Claude Code' })
  } catch {
    // no surface to notify on (a -p run): stay quiet
  }
  if (settings.hasSound) $.audio.play({ asset: sound }).catch(() => {})
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const stored = await $.store.get('settings')
    if (stored && typeof stored === 'object') settings = { ...DEFAULTS, ...(stored as Partial<Settings>) }
    await $.command.register({
      name: 'alerts',
      description: 'Done/needs-you alerts: on | off | sound on|off | after <seconds>',
      argumentHint: '[on|off|sound on|off|after <seconds>]',
    })
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    if (e.agentId || e.isAborted || e.durationMs < settings.afterSeconds * 1000) return result
    await alert($, e.reason === 'answer' ? `Done: ${firstLine(e.answer) || 'turn finished'}` : `Turn ended (${e.reason})`, 'sounds/done.wav')
    return result
  })

  on('tool.check', async ($, e, next) => {
    const verdict = await next(e)
    const now = await $.clock.now()
    if (verdict.decision === 'ask' && now - lastAskAt > 5000) {
      lastAskAt = now
      await alert($, `Needs your permission: ${String(e.tool)}`, 'sounds/attention.wav')
    }
    return verdict
  })

  on('tool.call', { tool: 'AskUserQuestion' }, async ($, e, next) => {
    await alert($, 'Claude is asking you a question', 'sounds/attention.wav')
    return next(e)
  })

  on('command.run', { command: 'alerts' }, async ($, e) => {
    const [a = '', b = ''] = e.args.trim().toLowerCase().split(/\s+/)
    if (a === 'on' || a === 'off') settings = { ...settings, isOn: a === 'on' }
    else if (a === 'sound' && (b === 'on' || b === 'off')) settings = { ...settings, hasSound: b === 'on' }
    else if (a === 'after' && Number(b) >= 0) settings = { ...settings, afterSeconds: Number(b) }
    else if (a !== '') return { text: `Not understood: "${e.args}". Try /alerts off, /alerts sound off, /alerts after 60.` }
    if (a !== '') await $.store.set('settings', settings)
    return {
      text: `Alerts ${settings.isOn ? 'on' : 'off'}, sound ${settings.hasSound ? 'on' : 'off'}; "done" after turns of ${settings.afterSeconds}s or more.`,
    }
  })
}
