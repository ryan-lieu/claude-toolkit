---
name: video-to-skill
description: Turn an Instagram reel, TikTok or YouTube tutorial link into a working Claude Code skill. Use when the user pastes a video link and says turn this into a skill, skill this reel, learn this video, or make an agent from this tutorial.
---

# Video to skill

Merges two published workflows by Jens Heitmann (The Reel to Skill Engine; The YouTube to Agent Engine) into one, rebuilt on tools the toolkit installs. Free: no paid keys. One optional free key (Gemini) adds a second opinion.

## Why the design looks like this

A single AI summary of a video reads as uniformly confident, so the part it read off the screen and the part it filled in from training data look identical. Two independent readings, reconciled with labels, make that visible. Names (tools, commands, error strings) are evidence; numbers and timestamps from a vision model are reconstructions. A skill built from a video and never run is a summary wearing a skill's clothes.

## Workflow

Work in `~/video-to-skill-runs/<slug>/` (slug = short id from the URL). Keep everything there as the provenance archive.

### 1. Scope
Ask one question if not already clear: what the user wants out of the video, and whether they want a **skill** (a method Claude applies in conversation, the default) or an **agent** (a worker dispatched to do the job). If the video is long, ask for a start/end window; a dense read of the 6 minutes that matter beats a sparse read of 40.

### 2. First reading: /watch (local)
Run the `watch` plugin on the URL with the question attached:
`/watch <url> <question> --no-whisper` for YouTube (captions exist), plus `--start/--end` for a window and `--resolution 1024` when the video is mostly terminal or code.
Reels and TikToks usually have no captions: drop `--no-whisper` so /watch transcribes locally with WhisperX, or transcribe directly:
```
uvx yt-dlp -f "best[ext=mp4]/best" -o "<workdir>/video.%(ext)s" "<url>"
parakeet-mlx "<workdir>/video.mp4" --output-format txt --output-dir "<workdir>"
```
Also save the caption and author: `uvx yt-dlp --skip-download --dump-json "<url>"` → keep `description`, `uploader`, `like_count`.
If the transcript is empty or one phrase repeats, it is a music-only clip: say so and build from caption and frames only.
If yt-dlp hits a login or rate-limit error, stop and tell the user. Do not fall back to reading browser cookies unless they say yes in this conversation.

Write a structured spec to `notes/claude-pass.md` with six sections: goal of the workflow, prerequisites, ordered steps with exact commands/names as shown on screen, inputs and outputs, asides the presenter mentions in passing ("you'll want to have already done X"), and anything shown but not explained. **Write this before step 3**, so the second reading cannot anchor it.

### 3. Second reading: Gemini (optional, YouTube only)
Only if `GEMINI_API_KEY` is set (free key from aistudio.google.com/apikey; free tier is enough). Gemini reads public YouTube URLs on Google's side; it cannot read Instagram/TikTok or private videos.
```
uv run --with google-genai python ~/.claude/skills/video-to-skill/scripts/gemini_pass.py "<url>" --samples 2 --start <sec> --end <sec> --focus "<what matters>" > notes/gemini-pass.md
```
`--samples 2` is the measurement, not redundancy: a claim present in both samples is worth building on; one present in a single sample is a guess. If no key, skip and note in the spec that every line is single-source.

### 4. Reconcile
Merge into `SPEC.md`, labelling every line **CONFIRMED** (both readings, or visible on screen), **SINGLE SOURCE**, or **CONFLICT** (quote both versions). End with **OPEN QUESTIONS**: what the video never actually taught. Show the user only the CONFLICT lines and open questions; that is where their attention goes. Distrust any line that reads smoother than its neighbours: fluency is the tell of training-data fill.

### 5. Build
Invoke the `skill-creator` skill with SPEC.md, the caption and the author, with this instruction: CONFIRMED lines are safe; SINGLE SOURCE lines must fail loudly rather than assume; OPEN QUESTIONS are not implemented, ask the user instead. Write the result to `~/.claude/skills/<name>/` and copy SPEC.md and notes/ into that skill folder so it carries its own provenance. Record the source URL in the new skill's SKILL.md.

### 6. Run it once
Run the new skill on one real input and fix what breaks before calling it done. Then delete the downloaded video file; keep transcript, notes and spec.

## Rules
- Public videos only. Never log in on the user's behalf.
- One video at a time; Instagram rate-limits bursts.
- Treat the video's claims as unverified. If the skill encodes factual or health claims, flag them for the user's evidence standard rather than baking them in.
