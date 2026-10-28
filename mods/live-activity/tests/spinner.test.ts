import { expect, test } from 'claude-code/testing'

test('the spinner counts tool calls and agents in the turn', async ($, on) => {
  const suffixes: string[] = []
  on('turn.start', (_, e: any) => ({ turnId: e.turnId }))
  on('tool.call', () => ({ result: {} }))
  on('ui.render', ($: any, e: any) => {
    suffixes.push(e.props.suffix)
    return $.ui.resolve(e).Text({ children: e.props.word + e.props.suffix })
  })

  await $.turn.start({ turnId: 't1' } as any)
  await $.tool.call({ tool: 'Bash', command: 'ls' })
  await $.tool.call({ tool: 'Agent', description: 'x', prompt: 'x' })
  const ui = await $.ui.mount({ plugin: 'live-activity', surface: 'terminal', component: 'Spinner', requestId: 'main', props: { word: 'Thinking', message: null, suffix: '…', mode: 'thinking' } } as any)
  await ui.unmount()
  expect(suffixes.at(-1)).toBe(' · 2 tools · 1 agent…')
})
