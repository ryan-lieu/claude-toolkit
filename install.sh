#!/bin/bash
# Install or update everything in manifest.txt on this Mac or Linux machine. Safe to re-run.
#   bash install.sh                  core tools
#   bash install.sh --with study     core + a group (study, heavy); repeat --with for more
#   bash install.sh --dry-run        show what would happen, change nothing (--check does the same)
#   bash install.sh --adopt          replace same-named skills that were installed by hand
#                                    (the old copy is moved to ~/.claude/skills-replaced/, not deleted)
#   bash install.sh NAME...          only these manifest entries, whatever their group
# It never replaces a skill it didn't install (unless --adopt), a same-named plugin from another
# marketplace, an existing MCP server, or a CLI tool that was installed some other way.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
dry=0; adopt=0; groups=" core "; names=""
while [ $# -gt 0 ]; do
  case "$1" in
    -n|--dry-run|--check) dry=1 ;;
    --with) shift; groups="$groups${1:-} " ;;
    --adopt) adopt=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    -*) echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
    *) names="$names $1 " ;;
  esac
  shift
done

os=linux; [ "$(uname -s)" = Darwin ] && os=mac
arch="$(uname -m)"
dest="$HOME/.claude/toolkit"            # clones of the skill repos; skills are symlinks into here
skills="$HOME/.claude/skills"
replaced="$HOME/.claude/skills-replaced/$(date +%Y%m%d-%H%M%S)"
log="${TMPDIR:-/tmp}/claude-toolkit-install.log"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/home/linuxbrew/.linuxbrew/bin:$PATH"
[ $dry = 1 ] && export HOMEBREW_NO_AUTO_UPDATE=1    # a dry run must not even refresh Homebrew
sudo=""; [ "$(id -u)" != 0 ] && command -v sudo >/dev/null && sudo="sudo"
has() { command -v "$1" >/dev/null 2>&1; }
n_ok=0; n_new=0; n_skip=0; n_fail=0

report() {  # status name detail
  printf '  %-8s %-30s %s\n' "$1" "$2" "$3"
  case "$1" in
    OK|UPDATE) n_ok=$((n_ok + 1)) ;;
    INSTALL|ADOPT|REMOVE) n_new=$((n_new + 1)) ;;
    SKIP) n_skip=$((n_skip + 1)) ;;
    FAIL) n_fail=$((n_fail + 1)) ;;
  esac
}
run() {  # run a command, output to the log; does nothing in a dry run
  [ $dry = 1 ] && return 0
  echo "+ $*" >>"$log"
  "$@" >>"$log" 2>&1
}
short() { echo "${1/#$HOME/~}"; }
would() { [ $dry = 1 ] && echo "would $1" || echo "$2"; }
sed_i() { sed -i.toolkit-bak "$1" "$2" && rm -f "$2.toolkit-bak"; }  # same on BSD and GNU sed

[ $dry = 1 ] && echo "DRY RUN: nothing will be changed." || : >"$log"
echo "Device: $os/$arch   groups:$groups  ${names:+only:$names}"

# ---------------------------------------------------------------- prerequisites
echo; echo "Prerequisites"
has git || { report FAIL git "git is required; install it and re-run"; exit 1; }
report OK git "$(git --version | cut -d' ' -f3)"
have_claude=0
if has claude; then have_claude=1; report OK claude "$(claude --version 2>/dev/null | head -1)"
else report FAIL claude "Claude Code CLI not found (https://code.claude.com); plugins and MCP servers will fail"; fi
if [ $os = mac ]; then
  if has brew; then report OK brew "$(brew --version 2>/dev/null | head -1)"
  else report SKIP brew "Homebrew not found (https://brew.sh); brew-only tools will fail"; fi
fi
if has uv; then report OK uv "$(uv --version | cut -d' ' -f2)"
else
  report INSTALL uv "$(would 'run the astral.sh installer' 'astral.sh installer')"
  run sh -c 'curl -LsSf https://astral.sh/uv/install.sh | sh' || report FAIL uv "see $log"
fi
if has uv && uv python find 3.12 >/dev/null 2>&1; then report OK python3.12 "$(short "$(uv python find 3.12)")"
else
  report INSTALL python3.12 "$(would 'run: uv python install 3.12' 'uv python install 3.12')"
  run uv python install 3.12 || report FAIL python3.12 "see $log"
fi

# ---------------------------------------------------------------- skills
synced=" "; badrepos=" "
repo_dir() { local s="${1#https://github.com/}"; s="${s%.git}"; echo "$dest/${s//\//__}"; }
sync_repo() {  # url dir ref: clone or fetch once per run, then check out the ref (or the default branch)
  case "$synced" in *" $2 "*) return 0 ;; esac
  case "$badrepos" in *" $2 "*) return 1 ;; esac
  synced="$synced$2 "
  if [ -d "$2/.git" ]; then run git -C "$2" fetch -q --tags origin
  else mkdir -p "$dest" && run git clone -q --filter=blob:none "$1" "$2"; fi &&
  run git -C "$2" checkout -qf --detach "${3:-origin/HEAD}" && return 0
  badrepos="$badrepos$2 "; return 1
}
skill_hook() {  # name dir target: extra setup after a skill is linked
  case "$1" in
    remotion-best-practices)  # upstream's description is too vague to trigger the skill
      sed_i 's/^description: Router for all Remotion skills$/description: Official Remotion skill for making videos with React code - new projects, animation, captions, audio, transitions, maps, Studio preview and rendering. Use for any Remotion or code-built video task./' "$3/SKILL.md" ;;
    find-skills)  # the skills CLI sends usage data unless told not to
      sed_i 's/DISABLE_TELEMETRY=1 npx skills /npx skills /g; s/npx skills /DISABLE_TELEMETRY=1 npx skills /g' "$3/SKILL.md" ;;
    shorts)  # Python venv (~/.shorts-skill, Python 3.12) + Remotion's node_modules, via the repo's own setup.sh
      if [ ! -d "$HOME/.video-skill" ] && [ ! -x "$HOME/.shorts-skill/bin/pip" ]; then
        run "$(uv python find 3.12)" -m venv "$HOME/.shorts-skill" || return 1
      fi
      run bash "$2/setup.sh" ;;
    manim-skill)  # Python env for manim and the Kokoro voiceover
      (cd "$2" && run uv sync -q --python 3.12) ;;
  esac
}
do_skill() {
  local dir="" target link="$skills/$name" verb cur before="" after=""
  if [ "$source" = local ]; then target="$here/$path"
  else dir="$(repo_dir "$source")"; target="$dir/$path"; target="${target%/.}"; fi
  if [ -L "$link" ]; then
    cur="$(readlink "$link")"
    case "$cur" in
      "$dest"/*|"$here"/*) verb=UPDATE ;;
      *) [ $adopt = 1 ] || { report SKIP "$name" "hand-made link to $(short "$cur") (left alone; --adopt replaces it)"; return; }
         verb=ADOPT ;;
    esac
  elif [ -e "$link" ]; then
    [ $adopt = 1 ] || { report SKIP "$name" "installed by hand (left alone; --adopt replaces it)"; return; }
    verb=ADOPT
  else verb=INSTALL; fi
  [ -n "$dir" ] && [ -d "$dir/.git" ] && before="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)"

  if [ $dry = 1 ]; then
    local at="${ref:-latest $(basename "$source")}"
    case "$verb" in
      INSTALL) report INSTALL "$name" "would link $(short "$target")${dir:+ @ $at}" ;;
      ADOPT)   report ADOPT "$name" "would move the hand-installed copy to $(short "$replaced") and link $(short "$target")${dir:+ @ $at}" ;;
      UPDATE)  if [ -z "$dir" ]; then report OK "$name" "linked to this repo"
               elif [ -n "$ref" ] && [[ "$before" == "$ref"* || "$ref" == "$before"* ]]; then report OK "$name" "pinned @ $ref"
               elif [ -z "$ref" ]; then report OK "$name" "@ ${before:-?}, unpinned; would pull the latest"
               else report UPDATE "$name" "would move ${before:-?} -> $ref"; fi ;;
    esac
    return
  fi

  if [ -n "$dir" ]; then sync_repo "$source" "$dir" "$ref" || { report FAIL "$name" "git clone/fetch of $source failed (see $log)"; return; }; fi
  [ -f "$target/SKILL.md" ] || { report FAIL "$name" "no SKILL.md at $(short "$target")"; return; }
  if [ $verb = ADOPT ]; then mkdir -p "$replaced" && mv "$link" "$replaced/$name" || { report FAIL "$name" "could not move the old copy"; return; }; fi
  mkdir -p "$skills" && ln -sfn "$target" "$link" || { report FAIL "$name" "could not link"; return; }
  skill_hook "$name" "$dir" "$target" || { report FAIL "$name" "linked, but its setup step failed (see $log)"; return; }
  [ -n "$dir" ] && after="$(git -C "$dir" rev-parse --short HEAD)"
  if [ $verb = UPDATE ]; then
    [ "$before" = "$after" ] && report OK "$name" "${after:-linked}" || report UPDATE "$name" "$before -> $after"
  else report "$verb" "$name" "-> $(short "$target")${after:+ @ $after}"; fi
}

# ---------------------------------------------------------------- plugins and MCP servers
plugins_now=""; mkts_now=""
if [ $have_claude = 1 ]; then
  plugins_now="$(claude plugin list 2>/dev/null)"
  mkts_now="$(claude plugin marketplace list 2>/dev/null)"
fi
do_plugin() {
  local plug="${name%@*}" mkt="${name#*@}" other
  [ $have_claude = 1 ] || { report FAIL "$name" "claude CLI not found"; return; }
  if grep -Eq "[[:space:]]$plug@$mkt\$" <<<"$plugins_now"; then
    [ $dry = 1 ] && { report OK "$name" "installed; would refresh $mkt and update it"; return; }
    run claude plugin marketplace update "$mkt"
    if run claude plugin update -s user "$name"; then report OK "$name" "up to date (restart Claude Code after updates)"
    else report FAIL "$name" "update failed (see $log)"; fi
    return
  fi
  other="$(grep -Eo "[[:space:]]$plug@[^[:space:]]+" <<<"$plugins_now" | grep -v '@synced$' | head -1 | tr -d '[:space:]')"
  [ -n "$other" ] && { report SKIP "$name" "a different '$plug' plugin is installed ($other); left alone"; return; }
  [ $dry = 1 ] && { report INSTALL "$name" "would add marketplace $source and install"; return; }
  if ! grep -Eq "[[:space:]]$mkt\$" <<<"$mkts_now"; then
    run claude plugin marketplace add "$source" || { report FAIL "$name" "could not add marketplace $source (see $log)"; return; }
    mkts_now="$mkts_now
 $mkt"
  fi
  if run claude plugin install -s user "$name"; then report INSTALL "$name" "from $source"
  else report FAIL "$name" "install failed (see $log)"; fi
}
do_mcp() {
  local cmd="$source${extra:+ $extra}"
  [ $have_claude = 1 ] || { report FAIL "$name" "claude CLI not found"; return; }
  if claude mcp get "$name" >/dev/null 2>&1; then report OK "$name" "already configured (left as is)"; return; fi
  [ $dry = 1 ] && { report INSTALL "$name" "would run: claude mcp add -s user $name -- $cmd"; return; }
  # shellcheck disable=SC2086
  if run claude mcp add -s user "$name" -- $cmd; then report INSTALL "$name" "$cmd"
  else report FAIL "$name" "claude mcp add failed (see $log)"; fi
}

# ---------------------------------------------------------------- CLI tools
cli_where() {
  case "$name" in
    mactex) [ -x /Library/TeX/texbin/pdflatex ] && echo /Library/TeX/texbin ;;
    whisperx) local p
      for p in "$HOME/.cache/watch/whisperx-venv/bin/whisperx" "$(command -v whisperx)"; do
        [ -n "$p" ] && [ -x "$p" ] && { echo "$p"; return; }
      done ;;
    *) command -v "$name" ;;
  esac
}
pypkg() { local p="${1%%[*}"; echo "${p%%[=<>]*}"; }
release_asset() {  # owner/repo -> download URL for this OS/CPU (auto-editor's naming)
  local o=linux a="$arch"
  [ $os = mac ] && o=macos
  [ $os = linux ] && [ "$a" = arm64 ] && a=aarch64
  [ $os = mac ] && [ "$a" = aarch64 ] && a=arm64
  echo "https://github.com/$1/releases/latest/download/$name-$o-$a"
}
resolve() { readlink -f "$1" 2>/dev/null || echo "$1"; }
cli_update() {  # tool is present: update it if one of our managers owns the copy on PATH; else leave it alone
  local alt mgr pkg where="$1" real; real="$(resolve "$1")"
  for alt in ${source//|/ }; do
    mgr="${alt%%:*}"; pkg="${alt#*:}"
    case "$mgr" in
      uv) has uv && uv tool list 2>/dev/null | grep -q "^$(pypkg "$pkg") " || continue
          case "$real" in "$(resolve "$(uv tool dir)")"/*) ;; *) continue ;; esac
          pkg="$(pypkg "$pkg")"
          if [ $dry = 1 ]; then
            uv tool list --outdated 2>/dev/null | grep -q "^$pkg " && report UPDATE "$name" "would run: uv tool upgrade $pkg" || report OK "$name" "uv tool, up to date"
          else run uv tool upgrade "$pkg" && report OK "$name" "uv tool, upgraded if needed" || report FAIL "$name" "uv tool upgrade failed (see $log)"; fi
          return ;;
      brew|cask) has brew || continue
          local c="--formula"; [ "$mgr" = cask ] && c="--cask"
          brew list $c "$pkg" >/dev/null 2>&1 || continue
          [ "$mgr" = cask ] || case "$real" in "$(resolve "$(brew --prefix)")"/*) ;; *) continue ;; esac
          if [ $dry = 1 ]; then
            [ -n "$(brew outdated $c "$pkg" 2>/dev/null)" ] && report UPDATE "$name" "would run: brew upgrade $c $pkg" || report OK "$name" "Homebrew, up to date"
          else run brew upgrade $c "$pkg" && report OK "$name" "Homebrew, upgraded if needed" || report FAIL "$name" "brew upgrade failed (see $log)"; fi
          return ;;
      apt) has dpkg && dpkg -s "$pkg" >/dev/null 2>&1 || continue
          [ $dry = 1 ] && { report OK "$name" "apt package; would run: apt-get install --only-upgrade $pkg"; return; }
          run $sudo apt-get install -y -q --only-upgrade "$pkg" && report OK "$name" "apt, upgraded if needed" || report FAIL "$name" "apt upgrade failed (see $log)"
          return ;;
      dnf) has rpm && rpm -q "$pkg" >/dev/null 2>&1 || continue
          [ $dry = 1 ] && { report OK "$name" "dnf package; would run: dnf upgrade $pkg"; return; }
          run $sudo dnf upgrade -y -q "$pkg" && report OK "$name" "dnf, upgraded if needed" || report FAIL "$name" "dnf upgrade failed (see $log)"
          return ;;
      release) [ -f "$dest/.release/$name" ] || continue
          [ $dry = 1 ] && { report OK "$name" "release binary; would re-download the latest"; return; }
          run curl -fsSL -o "$HOME/.local/bin/$name" "$(release_asset "$pkg")" && report OK "$name" "latest release" || report FAIL "$name" "download failed (see $log)"
          return ;;
      watch) case "$where" in "$HOME/.cache/watch/"*) report OK "$name" "managed by the watch plugin ($(short "$where"))"; return ;; esac ;;
    esac
  done
  report OK "$name" "present at $(short "$where") (installed outside the toolkit; left alone)"
}
cli_install() {
  local alt mgr pkg
  for alt in ${source//|/ }; do
    mgr="${alt%%:*}"; pkg="${alt#*:}"
    case "$mgr" in
      brew) has brew || continue
            [ $dry = 1 ] && { report INSTALL "$name" "would run: brew install $pkg"; return; }
            run brew install "$pkg" ;;
      cask) [ $os = mac ] && has brew || continue
            [ $dry = 1 ] && { report INSTALL "$name" "would run: brew install --cask $pkg (asks for your password)"; return; }
            run brew install --cask "$pkg" </dev/tty ;;
      apt)  [ $os = linux ] && has apt-get || continue
            [ $dry = 1 ] && { report INSTALL "$name" "would run: apt-get install $pkg"; return; }
            run $sudo apt-get install -y -q "$pkg" ;;
      dnf)  [ $os = linux ] && has dnf || continue
            [ $dry = 1 ] && { report INSTALL "$name" "would run: dnf install $pkg"; return; }
            run $sudo dnf install -y -q "$pkg" ;;
      uv)   has uv || [ $dry = 1 ] || continue
            [ $dry = 1 ] && { report INSTALL "$name" "would run: uv tool install $pkg"; return; }
            run uv tool install "$pkg" ;;
      release)
            [ $dry = 1 ] && { report INSTALL "$name" "would download $(release_asset "$pkg")"; return; }
            mkdir -p "$HOME/.local/bin" "$dest/.release" &&
            run curl -fsSL -o "$HOME/.local/bin/$name" "$(release_asset "$pkg")" &&
            chmod +x "$HOME/.local/bin/$name" && echo "$pkg" >"$dest/.release/$name" ;;
      watch) local setup
            setup="$(ls -d "$HOME"/.claude/plugins/cache/*/watch/*/skills/watch/scripts/setup.py 2>/dev/null | tail -1)"
            [ -n "$setup" ] || [ $dry = 1 ] || continue
            [ $dry = 1 ] && { report INSTALL "$name" "would run the watch plugin's setup.py --install-whisperx (~3 GB)"; return; }
            run uv run --no-project --python 3.12 python "$setup" --install-whisperx ;;
      *) continue ;;
    esac
    if [ $? = 0 ]; then report INSTALL "$name" "via $mgr"; else report FAIL "$name" "$mgr install failed (see $log)"; fi
    return
  done
  report FAIL "$name" "no way to install it here (needs one of: $source)"
}
do_cli() {
  local where; where="$(cli_where)"
  if [ -n "$where" ]; then cli_update "$where"; else cli_install; fi
}

# ---------------------------------------------------------------- walk the manifest
platform_ok() {
  case "$1" in
    all) return 0 ;;
    mac) [ $os = mac ] ;;
    mac-arm) [ $os = mac ] && [ "$arch" = arm64 ] ;;
    *) return 1 ;;
  esac
}
section=""; unselected=" "
while read -r type name platform group source extra <&3; do
  [[ -z "${type:-}" || "$type" == \#* ]] && continue
  if [ -n "$names" ]; then [[ "$names" == *" $name "* ]] || continue
  elif [[ "$groups" != *" $group "* ]]; then
    [[ "$unselected" == *" $group "* ]] || unselected="$unselected$group "
    continue
  fi
  if [ "$type" != "$section" ]; then
    section="$type"; echo
    case "$type" in skills) echo "Skills (~/.claude/skills)" ;; plugin) echo "Plugins" ;; mcp) echo "MCP servers" ;; cli) echo "CLI tools" ;; esac
  fi
  platform_ok "$platform" || { report SKIP "$name" "$platform only"; continue; }
  path="."; ref=""
  for kv in $extra; do case "$kv" in path=*) path="${kv#path=}" ;; ref=*) ref="${kv#ref=}" ;; esac; done
  case "$type" in
    skills) do_skill ;;
    plugin) do_plugin ;;
    mcp)    do_mcp ;;
    cli)    do_cli ;;
    *)      report FAIL "$name" "unknown type '$type' in manifest.txt" ;;
  esac
done 3<"$here/manifest.txt"

# ---------------------------------------------------------------- links to skills no longer in the manifest
if [ -z "$names" ] && [ -d "$skills" ]; then
  listed=" $(awk '$1 == "skills" { printf "%s ", $2 }' "$here/manifest.txt")"
  header=0
  for link in "$skills"/*; do
    [ -L "$link" ] || continue
    nm="$(basename "$link")"
    case "$(readlink "$link")" in "$dest"/*|"$here"/*) ;; *) continue ;; esac
    [[ "$listed" == *" $nm "* ]] && continue
    [ $header = 1 ] || { echo; echo "Removed from the manifest"; header=1; }
    report REMOVE "$nm" "$(would 'remove this toolkit link' 'link removed')"
    [ $dry = 1 ] || rm -f "$link"
  done
fi

echo
echo "Summary: $n_ok ok, $n_new $( [ $dry = 1 ] && echo 'to install/change' || echo 'installed/changed' ), $n_skip skipped, $n_fail failed."
[ "$unselected" != " " ] && echo "Not selected:$unselected(add with --with <group>)."
[ $dry = 0 ] && echo "Log: $log. Restart Claude Code to load new skills and plugins."
[ $n_fail = 0 ]
