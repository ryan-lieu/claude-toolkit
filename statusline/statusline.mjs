#!/usr/bin/env node
// claude-toolkit status line. Claude Code pipes session JSON on stdin; this prints one line:
//   Opus 5.5 │ ctx 43% ▰▰▰▱▱▱▱ │ 5h 23% · 7d 41% │ ⎇ main │ claude-toolkit
// Context turns yellow at 60% and red at 80%; usage limits the same at 70% / 90%.
// Fields: https://code.claude.com/docs/en/statusline
import { execFileSync } from 'node:child_process'
import { basename } from 'node:path'

const C = { dim: '\x1b[2m', red: '\x1b[31m', yellow: '\x1b[33m', green: '\x1b[32m', cyan: '\x1b[36m', reset: '\x1b[0m' }
const paint = (color, text) => `${color}${text}${C.reset}`
const tone = (pct, warn, bad) => (pct >= bad ? C.red : pct >= warn ? C.yellow : C.green)

let raw = ''
process.stdin.setEncoding('utf8')
process.stdin.on('data', chunk => (raw += chunk))
process.stdin.on('end', () => {
  let d = {}
  try { d = JSON.parse(raw) } catch {}
  const parts = []

  parts.push(paint(C.cyan, d.model?.display_name ?? 'Claude'))

  const pct = d.context_window?.used_percentage
  if (typeof pct === 'number') {
    const filled = Math.round(Math.min(100, pct) / 100 * 8)
    parts.push(paint(tone(pct, 60, 80), `ctx ${Math.round(pct)}% ${'▰'.repeat(filled)}${'▱'.repeat(8 - filled)}`))
  }

  const limits = []
  for (const [key, label] of [['five_hour', '5h'], ['seven_day', '7d']]) {
    const used = d.rate_limits?.[key]?.used_percentage
    if (typeof used === 'number') limits.push(paint(tone(used, 70, 90), `${label} ${Math.round(used)}%`))
  }
  if (limits.length) parts.push(limits.join(paint(C.dim, ' · ')))

  const dir = d.workspace?.current_dir ?? d.cwd
  if (dir) {
    try {
      const branch = execFileSync('git', ['branch', '--show-current'], { cwd: dir, timeout: 800, stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim()
      if (branch) parts.push(`⎇ ${branch}`)
    } catch {}
    parts.push(paint(C.dim, basename(dir)))
  }

  process.stdout.write(parts.join(paint(C.dim, ' │ ')))
})
