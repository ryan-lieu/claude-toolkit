---
name: music-finder
description: Find free Creative Commons music, jingles, stings and sound effects (CC0 / CC BY) on Openverse, then put a short numbered listening folder in front of a person with each track's licence and attribution. Use when someone needs an outro jingle, intro sting, background track or sound for a video and wants free, licence-safe options, or says "find music", "find a jingle", "search Openverse" or "royalty-free track".
---

# Music finder

Claude can't hear. So split the work: Claude searches by words and filters by licence and length, people listen to
a short list and pick. Never call a track "good", "fits" or "sounds like" anything: you only know its title, tags,
length and licence.

Tool: `python3 ~/.claude/skills/music-finder/scripts/music_finder.py` (standard library only; Openverse needs no key,
anonymous use is rate-limited, so search a few times, not dozens).

## Steps
1. **Brief.** Get the mood, the length (an outro jingle is a few seconds; set `--max-seconds`), what it's for, and the
   project's own music rules (in a repo, check its style guide and licence log first: some sources may be banned).
2. **Search wide, then narrow.** Run 3-5 searches with different words for the same mood (instrument, genre, "sting",
   "jingle", "logo", "outro"). Openverse matches titles, tags and descriptions, so plain words work best.
   ```
   music_finder.py search "ukulele jingle" --max-seconds 15
   music_finder.py search "happy outro sting" --category music --length shortest
   ```
   Leave `--category` off at first: most Freesound jingles have no category, so `--category music` hides them.
   Defaults: CC0 and CC BY only. The script refuses NC and ND licences (not safe on a monetised channel).
3. **Shortlist 6-10** across the searches from what you can see: length, tags, title, source, licence (prefer CC0:
   no credit line needed). Say why each made the list in words you can check ("4 s, tagged ukulele, jingle"), never
   how it sounds.
4. **Fetch into a listening folder** the person names (in a video project, its Drive `raw/music/candidates/`;
   never into git):
   ```
   music_finder.py get 2 5 9 --out "<folder>"
   ```
   Each track gets a number, a `.json` with its licence and attribution, and a line in `index.md`. These are the
   source's preview files (often MP3); for the final mix, download the original from the track's page.
5. **Optional: let Earshot pre-sort** (if `earshot` is installed: `install.sh --with heavy`, then
   `earshot doctor --fetch` once). It compares the audio itself with a description, so it catches what the tags miss
   (on 11 Nov it flagged a "jingle" that was a man shouting):
   ```
   earshot rank "a short cheerful musical jingle that ends a video, no voice" "<folder>"/*.mp3
   ```
   Drop anything it calls "no match" or that "sounds most like" speech, and pass on its order. Report its own words
   ("sounds most like a ukulele"), not your opinion of the sound. About 30 s per call while it loads its models.
6. **People listen and pick.** Then log only the winner: `music_finder.py license <id>` prints the attribution text
   for a CC BY credit and a ready line for a licence table (`| Track | Artist | Source | Licence | Mood | Date |
   Used in |`).

## Licence checks before anything is published
- CC BY: the credit goes in the video description, word for word from the attribution.
- Some Creative Commons tracks (Jamendo, ccMixter artists) are also registered with YouTube's Content ID and can
  still be claimed. Before upload, put the track in a private test upload or check the artist's page; CC0 from
  Freesound is the safest.
- Keep the track's page URL in the log: it's the proof of the licence at the time you took it.
