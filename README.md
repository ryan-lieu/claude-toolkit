# claude-toolkit

The Claude Code skills, plugins, MCP servers and command-line tools that Ryan, Connor and Manav share, for every
project. One list (`manifest.txt`), one installer (`install.sh`), the same setup on every Mac and in every cloud
session.

## Install on a new Mac
1. **Homebrew.** Open Terminal and check with `brew --version`. If it isn't there, paste the one-line command from
   https://brew.sh and type your Mac password when asked. Installing Homebrew also installs `git`.
2. **Claude Code.** Install it from https://code.claude.com, then run `claude` once and sign in.
3. **Get the toolkit.** The repo is public, so you don't need a GitHub login for this:
   ```bash
   git clone https://github.com/ryan-lieu/claude-toolkit ~/Projects/claude-toolkit
   cd ~/Projects/claude-toolkit
   ```
4. **Preview, then install:**
   ```bash
   ./install.sh --dry-run          # see what it would do; changes nothing
   ./install.sh                    # core tools; about 5-15 minutes the first time
   ```
   If some of these skills are already on your Mac (copied from Ryan's old toolkit zip), they show up as `SKIP`. Run
   `./install.sh --adopt` to let the toolkit manage them; your old copies are moved to `~/.claude/skills-replaced/`.
5. **Restart Claude Code.** Type `/` and the new skills and commands appear in the list.

Every line of output says `OK`, `INSTALL`, `UPDATE`, `ADOPT`, `REMOVE`, `SKIP` or `FAIL`. For a `FAIL`, read the log
named at the end, fix the cause, and run it again; it's safe to re-run. The installer adds `uv` and Python 3.12 itself.

Optional groups:
```bash
bash install.sh --with study    # K-Dense research and statistics skills
bash install.sh --with heavy    # WhisperX for /watch (~3 GB), MacTeX for manim maths (~5 GB, asks for your password), earshot (then `earshot doctor --fetch`, ~1.1 GB)
bash install.sh --with mods     # Claude Code mods and a status line (opt-in; see Mods below)
bash install.sh shorts mactex   # only the named entries, whatever their group
```

## Mods (opt-in: `--with mods`)

[Mods](https://code.claude.com/docs/en/plugins/mods) are plugins whose code runs inside Claude Code (v2.1.287+): they can draw bands and panes, restyle the spinner, and rewrite tool calls. **They run with your full user permissions**, so nobody gets them unless they ask for the group. This repo is their marketplace (`.claude-plugin/marketplace.json`), installed from your local clone, so `git pull` then `/reload-plugins` updates them.

| Mod | What it does | Costs usage? | Source |
|---|---|---|---|
| `token-weather` | Context-window forecast band above the prompt | No | Anthropic sample, patched to stack with other bands |
| `cache-keeper` | Prompt-cache countdown; asks before a cold-cache send rewrites a big context; `/keepwarm`, `/board`, `/handoff` | Only `/keepwarm` pings | Nate Herk (MIT) |
| `flightdeck` | `/flightdeck` side pane: context, cost, permission decisions, subagents | No | Stephen Casella (MIT) |
| `blast-radius` | Holds `rm -r`, force-push, `git reset --hard`, `git clean` and shows what they'd hit; Proceed / Cancel | No | Anthropic sample |
| `replay-theater` | `/replay` steps through the last turn's file edits | No | Anthropic sample |
| `model-router` | Explore/lookup subagents → Haiku, general-purpose → Sonnet, unless Claude named a model. `/router` to see counts or change rules | Saves | this repo |
| `live-activity` | Spinner shows tool calls and subagents this turn; status entry summarises the last turn | No | this repo |
| `next-steps` | Three suggested follow-ups as buttons after each answer; press fills the prompt, never sends. `/nextsteps off` | One Haiku call per answer | this repo |
| `done-alert` | Notification + chime when a turn of 30 s+ ends, or Claude needs permission / asks a question. `/alerts` | No | this repo |

Also in the group: `statusline/statusline.mjs` (model · context % · 5h/7d plan usage · git branch · folder). It is set only if you have no status line already.

Turn one off: `/plugin` → Installed → disable it. All of them for one session: `claude --safe-mode`. Vendored mods are pinned copies: each folder's `PROVENANCE.md` says where it came from, the commit, and anything changed. Before adding another, run `claude plugin validate <folder>` and read every `$.process`, `$.http`, `$.fs`, `$.env` and `$.model` call.

## Update
```bash
cd ~/Projects/claude-toolkit && git pull && bash install.sh
```
Every run is safe to repeat. It moves pinned skills to the pin in `manifest.txt` and unpinned ones to their repo's
latest commit. It also updates plugins, plus any CLI tool it manages through Homebrew, uv, apt or dnf. It removes its
own links to skills that were dropped from the manifest.

### What it never touches
- **Skills you installed by hand.** A skill folder or link in `~/.claude/skills` that the toolkit didn't create is
  reported as `SKIP` and left alone. If you want the toolkit to manage it from now on, run
  `bash install.sh --adopt` (or `--adopt NAME`). Your old copy is moved to `~/.claude/skills-replaced/<date>/`,
  never deleted.
- **A plugin with the same name from a different marketplace**, or an MCP server that already exists under the
  same name.
- **CLI tools installed some other way** (for example, Ryan's ffmpeg comes from pixi). They're reported as present
  and left alone.

## How it works
- Skill repos are cloned into `~/.claude/toolkit/`, and each skill is a symlink from `~/.claude/skills/<name>`
  into that clone (or into `skills/` in this repo). A link that points there is the toolkit's; anything else is
  yours.
- A few skills need a setup step after linking, in `skill_hook` in `install.sh`:
  - `shorts`: Python venv and Remotion packages.
  - `manim-skill`: `uv sync`.
  - `remotion-best-practices`: a sharper description so it actually triggers.
  - `find-skills`: telemetry turned off.
- Output is one line per tool: `OK`, `UPDATE`, `INSTALL`, `ADOPT`, `REMOVE`, `SKIP` or `FAIL`. Command output goes
  to the log file named at the end.

## Cloud sessions
Put this in the cloud environment's setup script (claude.ai, environment settings):
```bash
git clone -q https://github.com/ryan-lieu/claude-toolkit ~/claude-toolkit && bash ~/claude-toolkit/install.sh
```
Cloud sessions are Linux, so `mac` and `mac-arm` entries (parakeet-mlx, MacTeX) are skipped. ffmpeg and node come
from apt/dnf, and auto-editor from its GitHub release.

## Add a tool
You need write access to this repo; Ryan adds collaborators in the repo's GitHub settings. Without it, ask Ryan to
add the line.

1. Add one line to `manifest.txt` (the format is at the top of the file). Give a skill from someone else's repo its
   real repo URL plus `path=` and, ideally, `ref=<commit>`. For a skill we wrote ourselves, copy its folder into
   `skills/` and use `local path=skills/<name>`.
2. If it needs a setup step after install, add a case for it to `skill_hook` in `install.sh`.
3. Run `bash install.sh --dry-run NAME`, then `bash install.sh NAME`.
4. Commit and push. Everyone else runs `git pull && bash install.sh`.

## Not in here, on purpose
- **Account-level tools.** claude.ai connectors (Gmail, Drive, Notion and so on) and the plugins synced from
  claude.ai come with the shared login, so there is nothing to install.
- **Personal tools**: Anki MCP, Zotero (`zotero-cli`), the Obsidian plugin and Ryan's vault-only skills.
- **Herk Edit Kit** (`nateherkai/herk-edit-kit`). It's a project folder, not a global skill set. Clone it on its
  own and open Claude Code inside it. Its skills default to paid ElevenLabs transcription and to a command that
  reads the Claude login token, so they shouldn't load in every project.

## Rules
- Public repo: no API keys, tokens, personal notes or private data in any file or skill.
- One source per tool. If you install something new, add it here the same day.
