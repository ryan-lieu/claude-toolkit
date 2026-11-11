---
name: voice-score
description: Compare versions of the same voiceover or narration with numbers (estimated speech quality, hiss level in pauses, high-frequency hiss, gaps of digital silence) so people only need to listen to the best two or three. Use when choosing between denoise settings, TTS voices, takes or processing chains, or when someone asks "which of these sounds cleaner", "score these audio files" or "measure the hiss".
---

# Voice score

Claude can't hear, and people get tired comparing six near-identical clips. This measures the versions, ranks them,
and hands people a shorter list. People still make the call; never say a version "sounds" better.

```
~/.claude/skills/voice-score/scripts/voice_score.py v1.mp3 v2.mp3 v3.mp3
~/.claude/skills/voice-score/scripts/voice_score.py *.mp3 --json
```
Needs `uv` and `ffmpeg`. The first run downloads PyTorch (about 1 GB, cached by uv) and the SQUIM model (about 30 MB).
`--no-squim` skips the model and gives only the level measurements.

## Reading it
- **PESQ, STOI, SI-SDR** come from TorchAudio's SQUIM model, which estimates them from the clip alone (no clean
  reference). Higher is better. Gaps under about 0.1 PESQ or 1 dB SI-SDR are ties.
- **floor dB / hiss>4k**: the hiss level in pauses, and its high (squeaky) part. Lower is quieter. This is usually
  where denoise versions really differ.
- **silent %**: how much of the pause time is digital silence. Hiss that stops and starts around those gaps is easy
  to notice. **unsteady**: how much the hiss level wobbles in pauses; lower is smoother.
- **pauses s**: how much pause the level numbers rest on. Under a few seconds, treat them as a hint.
- Compare versions of the same words only. Different texts or voices change every number.

## How to report
Give the table, say which two or three to listen to and why, in measured terms ("3 has the least hiss above 4 kHz,
7 dB under 2; 2 and 3 tie on estimated quality"), and say what the numbers can't tell (clipped word starts, odd
inflection, whether the voice suits the video).
