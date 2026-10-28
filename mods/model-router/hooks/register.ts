// Model Router: picks a cheaper model for subagents whose work doesn't need the
// main thread's model. Rule-based on purpose: asking a model to choose a model
// on every call would spend tokens to save tokens.
//
// Rules, applied to each Agent tool call:
//   - Claude named a model in the call      -> left alone (an explicit choice wins)
//   - subagent_type "fork"                  -> left alone (forks always inherit)
//   - a lookup type (Explore, guides, ...)  -> the lookup model (default haiku)
//   - general-purpose or no type given      -> the worker model (default sonnet)
//   - Plan, and any plugin or custom agent  -> left alone (its own definition decides)
//
// /router                 counts for this session and the current rules
// /router off | on        turn routing off or on (remembered across sessions)
// /router lookup haiku    model for lookup subagents   (haiku | sonnet | opus | inherit)
// /router worker sonnet   model for general subagents  (haiku | sonnet | opus | inherit)

import type { Register } from 'claude-code'

type Model = 'haiku' | 'sonnet' | 'opus'
type Choice = Model | 'inherit'
type Settings = { isOn: boolean; lookup: Choice; worker: Choice }

const DEFAULTS: Settings = { isOn: true, lookup: 'haiku', worker: 'sonnet' }
const LOOKUP_TYPES = new Set(['Explore', 'claude-code-guide', 'statusline-setup'])
const WORKER_TYPES = new Set(['general-purpose', ''])
const CHOICES: readonly string[] = ['haiku', 'sonnet', 'opus', 'inherit']

let settings: Settings = { ...DEFAULTS }
let counts: Record<string, number> = {}
let kept = 0

function isChoice(v: unknown): v is Choice {
  return typeof v === 'string' && CHOICES.includes(v)
}

function summary(): string {
  const parts = Object.entries(counts).map(([m, n]) => `${n} ${m}`)
  return parts.length ? `router: ${parts.join(' · ')}` : 'router: on'
}

function rules(): string {
  return [
    `Routing is ${settings.isOn ? 'on' : 'off'}.`,
    `Lookup subagents (${[...LOOKUP_TYPES].join(', ')}): ${settings.lookup}.`,
    `General-purpose subagents: ${settings.worker}.`,
    'A model Claude names in the call, forks, Plan and plugin/custom agents are left alone.',
  ].join('\n')
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const stored = await $.store.get('settings')
    if (stored && typeof stored === 'object') {
      const s = stored as Partial<Settings>
      settings = {
        isOn: typeof s.isOn === 'boolean' ? s.isOn : DEFAULTS.isOn,
        lookup: isChoice(s.lookup) ? s.lookup : DEFAULTS.lookup,
        worker: isChoice(s.worker) ? s.worker : DEFAULTS.worker,
      }
    }
    counts = {}
    kept = 0
    await $.command.register({
      name: 'router',
      description: 'Model router: counts and rules; on | off | lookup <model> | worker <model>',
      argumentHint: '[on|off|lookup <model>|worker <model>]',
    })
    return next(e)
  })

  on('tool.call', { tool: 'Agent' }, async ($, e, next) => {
    if (!settings.isOn || e.model || e.subagent_type === 'fork') {
      kept += 1
      return next(e)
    }
    const type = e.subagent_type ?? ''
    const choice = LOOKUP_TYPES.has(type) ? settings.lookup : WORKER_TYPES.has(type) ? settings.worker : 'inherit'
    if (choice === 'inherit') {
      kept += 1
      return next(e)
    }
    counts[choice] = (counts[choice] ?? 0) + 1
    $.ui.status(summary())
    return next({ ...e, model: choice })
  }).catch(($, e, next) => next(e)) // if the router fails, the call runs as Claude wrote it

  on('command.run', { command: 'router' }, async ($, e) => {
    const [verb = '', value = ''] = e.args.trim().toLowerCase().split(/\s+/)
    if (verb === 'on' || verb === 'off') {
      settings = { ...settings, isOn: verb === 'on' }
    } else if ((verb === 'lookup' || verb === 'worker') && isChoice(value)) {
      settings = { ...settings, [verb]: value }
    } else if (verb !== '') {
      return { text: `Not understood: "${e.args}".\n\n${rules()}` }
    }
    if (verb !== '') await $.store.set('settings', settings)
    const routed = Object.entries(counts).map(([m, n]) => `${n} to ${m}`).join(', ') || 'none yet'
    return { text: `${rules()}\n\nThis session: routed ${routed}; left alone ${kept}.` }
  })
}
