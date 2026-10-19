# claude-toolkit

The Claude Code skills, plugins, MCP servers and command-line tools that Ryan, Connor and Manav share, for every
project. One list (`manifest.txt`), one installer (`install.sh`), the same setup on every Mac and in every cloud
session.

## Install or update on a Mac
```bash
git clone https://github.com/ryan-lieu/claude-toolkit ~/Projects/claude-toolkit   # first time
cd ~/Projects/claude-toolkit && git pull && bash install.sh                        # every time after
bash install.sh --with study    # also Ryan's notes/science tools (Obsidian, K-Dense science skills, Anki)
bash install.sh --check         # list what's missing on this device, change nothing
```
Needs Homebrew, `uv` and Claude Code. It never overwrites a skill or plugin you installed by hand.

## Cloud sessions
Put this in the cloud environment's setup script (claude.ai, environment settings):
```bash
git clone -q https://github.com/ryan-lieu/claude-toolkit ~/claude-toolkit && bash ~/claude-toolkit/install.sh
```
Cloud sessions are Linux, so Mac-only tools (Homebrew, `parakeet-mlx`, Anki) are skipped.

## Add a tool
1. Add a line to `manifest.txt` (format at the top of the file). For a skill with no outside repo, copy its
   folder into `skills/`.
2. Commit and push. Everyone else runs `git pull && bash install.sh`.

## Rules
- Public repo: no API keys, tokens, personal notes or private data in any file or skill.
- One source per tool. If you install something new, add it here the same day.
