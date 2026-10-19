"""Second, independent reading of a public YouTube video with Gemini (free tier).

Usage: uv run --with google-genai python gemini_pass.py URL [--samples 2] [--start S] [--end S] [--focus TEXT] [--fps 1]
Needs GEMINI_API_KEY. Picks available *flash* models automatically, newest first,
because free keys list pro models but return 429 when called and model names change often.
"""
import argparse, os, sys

from google import genai
from google.genai import types

PROMPT = """You are writing a build spec from this video. Use only what is shown or said in the video.
Sections: 1 Goal, 2 Prerequisites, 3 Ordered steps with exact commands/tool names as shown,
4 Inputs and outputs, 5 Asides the presenter mentions in passing, 6 Things shown but not explained.
Quote commands verbatim. If you are unsure of a detail, write UNSURE instead of guessing.
Focus: {focus}"""


def flash_models(client):
    override = os.environ.get("GEMINI_MODEL")
    if override:
        return [override]
    names = []
    for m in client.models.list():
        n = m.name.split("/")[-1]
        actions = getattr(m, "supported_actions", None) or []
        if "flash" in n and "lite" not in n and "image" not in n and "tts" not in n and "live" not in n \
                and (not actions or "generateContent" in actions):
            names.append(n)
    return sorted(set(names), reverse=True)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("url")
    p.add_argument("--samples", type=int, default=2)
    p.add_argument("--start", type=int)
    p.add_argument("--end", type=int, default=600)
    p.add_argument("--fps", type=float, default=1.0)
    p.add_argument("--focus", default="the whole workflow")
    a = p.parse_args()
    if not os.environ.get("GEMINI_API_KEY"):
        sys.exit("GEMINI_API_KEY not set; skip the second reading.")
    client = genai.Client()
    meta = types.VideoMetadata(
        start_offset=f"{a.start}s" if a.start is not None else None,
        end_offset=f"{a.end}s" if a.end is not None else None,
        fps=a.fps,
    )
    part = types.Part(file_data=types.FileData(file_uri=a.url), video_metadata=meta)
    models = flash_models(client)
    for i in range(a.samples):
        for model in models:
            try:
                r = client.models.generate_content(
                    model=model, contents=types.Content(parts=[part, types.Part(text=PROMPT.format(focus=a.focus))]))
                print(f"## Sample {i + 1} ({model})\n\n{r.text}\n")
                break
            except Exception as e:  # fall forward to the next model
                print(f"<!-- {model} failed: {str(e)[:120]} -->", file=sys.stderr)
        else:
            sys.exit("All flash models failed. Check the current Gemini model list.")


if __name__ == "__main__":
    main()
