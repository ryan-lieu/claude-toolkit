import { expect, test } from 'claude-code/testing'

const BAND = {
  plugin: 'next-steps',
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: false, maxRows: 10, bodyColumns: 100, scroll: { offset: 0, bodyRows: 10 }, view: {} },
} as const

test('three suggestions become buttons; pressing one fills the prompt', async ($, on) => {
  const filled: string[] = []
  on('command.register', () => ({ value: { command: 'nextsteps' } }))
  on('store.get', () => ({ value: undefined }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('prompt.submit', (_, e: any) => ({ text: e.text }))
  on('model.complete', () => ({ value: { isAnswered: true, text: '1. Run the tests\n- Commit this\nExplain the router', usage: { input_tokens: 1, output_tokens: 1, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 } } }))
  on('prompt.fill', (_, e) => { filled.push(e.text); return { isFilled: true, cursor: 0 } })
  on('turn.complete', (_, e: any) => ({ text: e.answer }))
  on('ui.render', ($: any, e: any) => $.ui.resolve(e).Box({}))

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await $.prompt.submit({ text: 'add a router' } as any)
  await $.turn.complete({ answer: 'Added the router.', durationMs: 1000, isAborted: false, turnId: 't1', reason: 'answer' } as any)

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...BAND, surface } as any)
    expect((await ui.find({ key: 'next-0' }))?.text).toContain('Run the tests')
    expect((await ui.find({ key: 'next-1' }))?.text).toContain('Commit this')
    if (surface === 'desktop') await ui.press({ key: 'next-2' })
    await ui.unmount()
  }
  expect(filled).toEqual(['Explain the router'])
})
