#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10,<3.13"
# dependencies = ["numpy<3", "torch==2.8.*", "torchaudio==2.8.*"]
# ///
"""Score versions of the same narration with numbers, so people only listen to the best two or three.

Claude can't hear. This gives it measurements to compare versions of one recording (denoise settings, voices,
processing chains) and tells you what each number means. It never replaces listening.

  voice_score.py a.mp3 b.mp3 c.wav            # table, best first by estimated quality
  voice_score.py *.mp3 --json                 # machine-readable
  voice_score.py *.mp3 --no-squim             # level measurements only (no model download)

Measurements:
  PESQ, STOI, SI-SDR  TorchAudio SQUIM (Kumar et al. 2023): estimates of speech quality (PESQ 1-4.5),
                      intelligibility (STOI 0-1) and how much of the signal is speech rather than noise (SI-SDR, dB),
                      predicted from the clip alone. Higher is better. Trained on English read speech with added
                      noise, so treat small differences (under ~0.1 PESQ, ~1 dB SI-SDR) as ties.
  Pauses are runs of 160 ms+ at least 30 dB under the speech level; the level numbers come only from them.
  floor dB            median level of the hiss in pauses (digital silence left out). Lower is quieter.
  hiss>4k dB          the same, above 4 kHz only: the high, squeaky part of the hiss. Lower is quieter.
  silent %            share of pause time that is digital silence (inserted gaps, or a gate closing). Hiss that
                      stops and starts around those is easy to notice, so a mix of high floor and high silent % is
                      the worst case; near 0% or near 100% is steadier.
  unsteady dB         spread of the hiss level within pauses. Lower is smoother.
  speech dB           level of the loudest 5% of frames, to check versions are compared at similar loudness.

First run downloads Python packages (about 1 GB, cached by uv) and the SQUIM model (about 30 MB).
"""
import argparse
import json
import os
import subprocess
import sys

import numpy as np

SR = 16000
FRAME = 320  # 20 ms


def decode(path, af=None):
    cmd = ["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(SR)] + (["-af", af] if af else []) + [
        "-f", "f32le", "-"]
    try:
        raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    except FileNotFoundError:
        sys.exit("ffmpeg isn't installed.")
    except subprocess.CalledProcessError as e:
        sys.exit(f"Couldn't decode {path}: {e.stderr.decode()[:200]}")
    return np.frombuffer(raw, dtype=np.float32).copy()


def db(x):
    return 20 * np.log10(np.maximum(x, 1e-9))


def frame_db(x):
    n = len(x) // FRAME
    return db(np.sqrt((x[: n * FRAME].reshape(n, FRAME) ** 2).mean(axis=1)))


def levels(x, x_hi):
    rms_db = frame_db(x)
    hi_db = frame_db(x_hi)[: len(rms_db)]
    n = len(rms_db)
    speech_lvl = np.percentile(rms_db, 95)
    # pauses: runs of 160 ms or more at least 30 dB under the speech level
    low = rms_db < speech_lvl - 30
    pause = np.zeros(n, bool)
    i = 0
    while i < n:
        if low[i]:
            j = i
            while j < n and low[j]:
                j += 1
            if j - i >= 8:
                pause[i + 1:j - 1] = True  # drop the edge frames, which carry word tails
            i = j
        else:
            i += 1
    p = rms_db[pause]
    silent = p < -90  # digital silence: inserted gaps or a closed gate
    live = p[~silent]
    floor = float(np.median(live)) if live.size else float("nan")
    hiss = float(np.median(hi_db[pause][~silent])) if live.size else float("nan")
    return {"pause_s": round(pause.sum() * FRAME / SR, 1),
            "floor_db": round(floor, 1), "hiss_4k_db": round(hiss, 1),
            "silent_pct": round(100 * silent.mean(), 0) if p.size else None,
            "steadiness_db": round(float(np.std(live)), 1) if live.size else None,
            "speech_db": round(float(speech_lvl), 1)}


_model = None


def squim(x):
    global _model
    import torch
    import torchaudio
    if _model is None:
        _model = torchaudio.pipelines.SQUIM_OBJECTIVE.get_model().eval()
    seg = SR * 10
    out = []
    with torch.inference_mode():
        for s in range(0, len(x), seg):
            chunk = x[s:s + seg]
            if len(chunk) < SR * 3:
                continue
            stoi, pesq, sisdr = _model(torch.from_numpy(chunk).unsqueeze(0))
            out.append((len(chunk), float(stoi), float(pesq), float(sisdr)))
    if not out:
        return {}
    w = np.array([o[0] for o in out], dtype=float)
    avg = lambda k: float((np.array([o[k] for o in out]) * w).sum() / w.sum())
    return {"stoi": round(avg(1), 3), "pesq": round(avg(2), 2), "si_sdr": round(avg(3), 1)}


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("files", nargs="+")
    p.add_argument("--json", action="store_true")
    p.add_argument("--no-squim", action="store_true", help="skip the model; level measurements only")
    a = p.parse_args()
    rows = []
    for f in a.files:
        x = decode(f)
        r = {"file": os.path.basename(f), **levels(x, decode(f, "highpass=f=4000,highpass=f=4000"))}
        if not a.no_squim:
            r.update(squim(x))
        rows.append(r)
    if not a.no_squim:
        rows.sort(key=lambda r: -(r.get("pesq") or 0))
    if a.json:
        print(json.dumps(rows, indent=1))
        return
    cols = ([("pesq", "PESQ"), ("stoi", "STOI"), ("si_sdr", "SI-SDR")] if not a.no_squim else []) + [
        ("floor_db", "floor dB"), ("hiss_4k_db", "hiss>4k"), ("silent_pct", "silent %"),
        ("steadiness_db", "unsteady"), ("pause_s", "pauses s"), ("speech_db", "speech dB")]
    w = max(len(r["file"]) for r in rows)
    print(f"{'file':<{w}}  " + "  ".join(f"{h:>9}" for _, h in cols))
    for r in rows:
        print(f"{r['file']:<{w}}  " + "  ".join(f"{'' if r.get(k) is None else r.get(k):>9}" for k, _ in cols))
    print("\nHigher PESQ/STOI/SI-SDR is better; lower floor, hiss and unsteady are better. Small gaps are ties."
          " Listen to the top two or three before deciding.")


if __name__ == "__main__":
    main()
