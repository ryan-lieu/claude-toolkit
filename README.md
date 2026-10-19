# claude-toolkit

The Claude Code skills, plugins, MCP servers and command-line tools that Ryan, Connor and Manav share, for every
project. One list (`manifest.txt`), one installer (`install.sh`), the same setup on every Mac and in every cloud
session.

## Install
```bash
git clone https://github.com/ryan-lieu/claude-toolkit ~/Projects/claude-toolkit
cd ~/Projects/claude-toolkit
bash install.sh --dry-run       # see what it would do; changes nothing
bash install.sh                 # core tools
```
Needs `git` and Claude Code (signed in). On a Mac, also Homebrew (https://brew.sh). The installer adds `uv` and
Python 3.12 itself if they're missing. Restart Claude Code afterwards so it picks up new skills and plugins.

Optional groups:
```bash
bash install.sh --with study    # K-Dense research and statistics skills
bash install.sh --with heavy    # WhisperX for /watch (~3 GB) and MacTeX for manim maths (~5 GB, asks for your password)
bash install.sh shorts mactex   # only the named entries, whatever their group
```

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
