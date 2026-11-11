#!/usr/bin/env python3
"""Find Creative Commons music and sounds on Openverse, then fetch a shortlist for people to listen to.

Claude can't hear audio, so this does the part it can: search by words, filter by licence and length, and hand
people a small numbered folder with each track's licence and attribution beside it. Standard library only.

  music_finder.py search "upbeat ukulele jingle" --max-seconds 15
  music_finder.py search "cheerful outro" --license cc0 --category music --n 30 --json
  music_finder.py get 3 5 7 --out ~/Desktop/outro-shortlist        # numbers from the last search
  music_finder.py get <openverse-id> --out DIR
  music_finder.py license <openverse-id>                            # the attribution and a log line

Licences: cc0 (no attribution) and by (credit the creator) are the defaults. by-sa works but anything built from it
must share alike; nc and nd are never safe on a monetised channel, so this script refuses them.
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.openverse.org/v1/audio/"
UA = "claude-toolkit-music-finder/1.0"
CACHE = os.path.expanduser("~/.cache/music-finder/last-search.json")
SAFE_LICENSES = {"cc0", "pdm", "by", "by-sa"}
LENGTHS = {"shortest": "under 30 s", "short": "30 s-2 min", "medium": "2-10 min", "long": "over 10 min"}


def fetch_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < 2:
                time.sleep(5 * (attempt + 1))
                continue
            body = e.read().decode("utf-8", "replace")[:300]
            sys.exit(f"Openverse said {e.code}: {body}")
        except urllib.error.URLError as e:
            sys.exit(f"Couldn't reach Openverse: {e.reason}")


def seconds(item):
    d = item.get("duration")
    return d / 1000 if isinstance(d, (int, float)) else None


def fmt_len(s):
    return "?" if s is None else f"{int(s // 60)}:{int(round(s % 60)):02d}"


def search(a):
    licenses = [x.strip() for x in a.license.split(",") if x.strip()]
    bad = [x for x in licenses if x not in SAFE_LICENSES]
    if bad:
        sys.exit(f"Refusing licence(s) {', '.join(bad)}: only {', '.join(sorted(SAFE_LICENSES))} are safe for a "
                 "monetised channel.")
    params = {"q": a.query, "license": ",".join(licenses), "page_size": 20, "mature": "false"}
    if a.category:
        params["category"] = a.category
    if a.length:
        params["length"] = a.length
    if a.source:
        params["source"] = a.source
    found, page = [], 1
    while len(found) < a.n and page <= a.pages:
        data = fetch_json(API + "?" + urllib.parse.urlencode({**params, "page": page}))
        results = data.get("results", [])
        for r in results:
            s = seconds(r)
            if a.max_seconds and (s is None or s > a.max_seconds):
                continue
            if a.min_seconds and (s is None or s < a.min_seconds):
                continue
            found.append(r)
        if page >= (data.get("page_count") or 1) or not results:
            break
        page += 1
    found = found[: a.n]
    if found:  # an empty search keeps the previous list, so its numbers still work
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        with open(CACHE, "w") as f:
            json.dump({"query": a.query, "results": found}, f)
    if a.json:
        print(json.dumps([slim(r) for r in found], indent=1))
        return
    if not found:
        print("Nothing matched. Try fewer words, drop --max-seconds, or --length short.")
        return
    print(f'{len(found)} results for "{a.query}" ({",".join(licenses)}). Fetch with: get <number> ...\n')
    for i, r in enumerate(found, 1):
        tags = ", ".join(t["name"] for t in (r.get("tags") or [])[:6])
        print(f"{i:>3}. {r.get('title') or '(untitled)'}  [{fmt_len(seconds(r))}]  {lic(r)}  by {r.get('creator')} "
              f"({r.get('source')})")
        if tags:
            print(f"     tags: {tags}")
        print(f"     {r.get('foreign_landing_url')}")


def lic(r):
    v = r.get("license_version") or ""
    return f"CC {r.get('license', '').upper()} {v}".strip() if r.get("license") not in ("cc0", "pdm") else (
        "CC0" if r.get("license") == "cc0" else "Public domain")


def slim(r):
    return {"id": r["id"], "title": r.get("title"), "creator": r.get("creator"), "seconds": seconds(r),
            "license": lic(r), "attribution_needed": r.get("license") not in ("cc0", "pdm"),
            "source": r.get("source"), "page": r.get("foreign_landing_url"), "audio": r.get("url"),
            "tags": [t["name"] for t in (r.get("tags") or [])], "attribution": r.get("attribution")}


def resolve(ref):
    if ref.isdigit():
        try:
            cached = json.load(open(CACHE))["results"]
        except (OSError, KeyError, ValueError):
            sys.exit("No saved search: run `search` first, or pass an Openverse id.")
        n = int(ref)
        if not 1 <= n <= len(cached):
            sys.exit(f"Number {n} isn't in the last search (1-{len(cached)}).")
        return cached[n - 1]
    return fetch_json(API + urllib.parse.quote(ref) + "/")


def safe_name(s):
    return re.sub(r"[^A-Za-z0-9]+", "-", s or "track").strip("-").lower()[:50] or "track"


def get(a):
    out = os.path.expanduser(a.out)
    os.makedirs(out, exist_ok=True)
    existing = len([f for f in os.listdir(out) if f.endswith(".json")])
    rows = []
    picked = [resolve(ref) for ref in a.refs]  # check every number before downloading anything
    for k, r in enumerate(picked, existing + 1):
        if r.get("license") not in SAFE_LICENSES:
            print(f"SKIP {r.get('title')}: licence {r.get('license')} isn't safe for a monetised channel.")
            continue
        ext = (r.get("filetype") or "mp3").lower()
        base = f"{k:02d}-{safe_name(r.get('title'))}"
        path = os.path.join(out, f"{base}.{ext}")
        req = urllib.request.Request(r["url"], headers={"User-Agent": UA})
        try:
            with urllib.request.urlopen(req, timeout=60) as resp, open(path, "wb") as f:
                f.write(resp.read())
        except (urllib.error.URLError, OSError) as e:
            print(f"FAIL {r.get('title')}: {e}")
            continue
        info = slim(r)
        info["file"] = os.path.basename(path)
        with open(os.path.join(out, base + ".json"), "w") as f:
            json.dump(info, f, indent=1)
        rows.append(info)
        print(f"OK   {info['file']}  [{fmt_len(info['seconds'])}]  {info['license']}")
    if rows:
        with open(os.path.join(out, "index.md"), "a") as f:
            for i in rows:
                need = "credit needed: " + (i["attribution"] or "") if i["attribution_needed"] else "no credit needed"
                f.write(f"- **{i['file']}**: {i['title']} by {i['creator']}, {fmt_len(i['seconds'])}, {i['license']} "
                        f"({need}). {i['page']}\n")
        print(f"\nListen in {out} (index.md lists them). Nothing is logged as used until someone picks one.")


def license_line(a):
    i = slim(resolve(a.ref))
    print(i["attribution"] or f'"{i["title"]}" by {i["creator"]}, {i["license"]}')
    print(f"\nLog line: | {i['title']} | {i['creator']} | Openverse ({i['source']}): {i['page']} | {i['license']} "
          f"({'attribution needed' if i['attribution_needed'] else 'no attribution'}) | <mood> | "
          f"{time.strftime('%Y-%m-%d')} | <video> |")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("search", help="search Openverse audio")
    s.add_argument("query")
    s.add_argument("--license", default="cc0,by", help="comma list from cc0, pdm, by, by-sa (default cc0,by)")
    s.add_argument("--category", choices=["music", "sound_effect", "podcast", "audiobook", "news", "pronunciation"])
    s.add_argument("--length", choices=list(LENGTHS), help="Openverse's length bucket: " +
                   ", ".join(f"{k} = {v}" for k, v in LENGTHS.items()))
    s.add_argument("--source", help="e.g. freesound, jamendo, ccmixter, wikimedia_audio")
    s.add_argument("--max-seconds", type=float)
    s.add_argument("--min-seconds", type=float)
    s.add_argument("--n", type=int, default=20, help="results to show (default 20)")
    s.add_argument("--pages", type=int, default=5, help="pages of 20 to scan when filtering (default 5)")
    s.add_argument("--json", action="store_true")
    s.set_defaults(func=search)
    g = sub.add_parser("get", help="download tracks into a listening folder with their licences")
    g.add_argument("refs", nargs="+", help="numbers from the last search, or Openverse ids")
    g.add_argument("--out", required=True)
    g.set_defaults(func=get)
    l = sub.add_parser("license", help="attribution text and a licence-log line for one track")
    l.add_argument("ref")
    l.set_defaults(func=license_line)
    a = p.parse_args()
    a.func(a)


if __name__ == "__main__":
    main()
