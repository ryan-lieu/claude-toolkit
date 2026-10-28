import { expect, test } from 'claude-code/testing'

function engine(on: any) {
  on('command.register', () => ({ value: { command: 'router' } }))
  on('store.get', () => ({ value: undefined }))
  on('session.start', (_: unknown, e: { cwd: string }) => ({ cwd: e.cwd }))
}

async function start($: any) {
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
}

function spy(on: any): Array<string | undefined> {
  const seen: Array<string | undefined> = []
  on('tool.call', (_: unknown, e: { model?: string }) => {
    seen.push(e.model)
    return { result: {} }
  })
  return seen
}

test('lookup agents go to haiku, general ones to sonnet', async ($, on) => {
  engine(on)
  const seen = spy(on)
  await start($)
  await $.tool.call({ tool: 'Agent', description: 'find', prompt: 'x', subagent_type: 'Explore' })
  await $.tool.call({ tool: 'Agent', description: 'do', prompt: 'x', subagent_type: 'general-purpose' })
  await $.tool.call({ tool: 'Agent', description: 'do', prompt: 'x' })
  expect(seen).toEqual(['haiku', 'sonnet', 'sonnet'])
})

test('an explicit model, a fork, Plan and custom agents are left alone', async ($, on) => {
  engine(on)
  const seen = spy(on)
  await start($)
  await $.tool.call({ tool: 'Agent', description: 'a', prompt: 'x', subagent_type: 'Explore', model: 'opus' })
  await $.tool.call({ tool: 'Agent', description: 'b', prompt: 'x', subagent_type: 'fork' })
  await $.tool.call({ tool: 'Agent', description: 'c', prompt: 'x', subagent_type: 'Plan' })
  await $.tool.call({ tool: 'Agent', description: 'd', prompt: 'x', subagent_type: 'design:critic' })
  expect(seen).toEqual(['opus', undefined, undefined, undefined])
})
