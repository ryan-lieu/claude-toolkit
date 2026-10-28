// Next Steps: after Claude answers, three likely follow-ups appear as buttons
// above the prompt. Pressing one puts its text in the prompt box to edit or
// send; nothing is sent for you.
//
// Cost: one Haiku call per answered turn, sent only your last prompt and the
// end of Claude's answer (no history, no files). /nextsteps off stops it.

import type { Register } from 'claude-code'

const MAX_ANSWER = 3000
const MAX_PROMPT = 800

let isOn = true
let lastPrompt = ''
let suggestions: string[] = []
let turn = 0 // stale-answer guard: a slow suggestion for an old turn is dropped

const SYSTEM =
  'You suggest what a user is most likely to ask an AI coding assistant next. ' +
  'Reply with exactly three lines, each a request the user could type, in their voice, ' +
  'under 70 characters, specific to the conversation. No numbering, quotes or commentary.'

function parse(text: string): string[] {
  return text
    .split('\n')
    .map(l => l.replace(/^\s*(?:[-*•]|\d+[.)])\s*/, '').replace(/^["']|["']$/g, '').trim())
    .filter(l => l.length > 0 && l.length <= 120)
    .slice(0, 3)
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const stored = await $.store.get('isOn')
    if (typeof stored === 'boolean') isOn = stored
    await $.command.register({
      name: 'nextsteps',
      description: 'Suggested follow-up buttons after each answer: on | off',
      argumentHint: '[on|off]',
    })
    return next(e)
  })

  on('prompt.submit', ($, e, next) => {
    lastPrompt = e.text.slice(0, MAX_PROMPT)
    turn += 1
    if (suggestions.length) {
      suggestions = []
      $.ui.invalidate('ui.render')
    }
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    if (!isOn || e.agentId || e.reason !== 'answer' || e.answer.trim() === '') return result
    const mine = turn
    const reply = await $.model.complete({
      model: 'haiku',
      system: SYSTEM,
      prompt: `User's last request:\n${lastPrompt}\n\nEnd of the assistant's answer:\n${e.answer.slice(-MAX_ANSWER)}`,
      maxTokens: 200,
      timeoutMs: 15000,
    })
    if (mine !== turn || !reply.isAnswered) return result
    suggestions = parse(reply.text)
    $.ui.invalidate('ui.render')
    return result
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const below = await next(e)
    if (!isOn || suggestions.length === 0 || e.props.isWorking || e.props.hasSurvey) return below
    const { Box, Text, Button } = $.ui.resolve(e)
    const buttons = suggestions.map((s, i) =>
      Button({
        key: `next-${i}`,
        label: s,
        plain: true,
        onPress: async () => {
          await $.prompt.fill({ text: s, mode: 'replace' })
          suggestions = []
          $.ui.invalidate('ui.render')
        },
      }),
    )
    const dismiss = Button({
      key: 'next-dismiss',
      label: '×',
      plain: true,
      onPress: () => {
        suggestions = []
        $.ui.invalidate('ui.render')
      },
    })
    const mine = Box({
      flexDirection: 'row',
      flexWrap: 'wrap',
      columnGap: 3,
      paddingX: 1,
      children: [Text({ dimColor: true, children: 'next ›' }), ...buttons, dismiss],
    })
    return below ? Box({ flexDirection: 'column', children: [mine, below] }) : mine
  })

  on('command.run', { command: 'nextsteps' }, async ($, e) => {
    const arg = e.args.trim().toLowerCase()
    if (arg === 'on' || arg === 'off') {
      isOn = arg === 'on'
      await $.store.set('isOn', isOn)
      if (!isOn) {
        suggestions = []
        $.ui.invalidate('ui.render')
      }
    }
    return { text: `Next-step suggestions are ${isOn ? 'on' : 'off'}. Each costs one small Haiku call per answer.` }
  })
}
