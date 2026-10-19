#!/bin/bash
# Install or update everything in manifest.txt on this device. Safe to re-run: it adds and updates, and never
# replaces a skill or plugin someone installed by hand.
#   bash install.sh                 core tools
#   bash install.sh --with study    core + study tools
#   bash install.sh --check         report what's missing, change nothing
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
check=0; groups="core"
while [ $# -gt 0 ]; do
  case "$1" in
    --check) check=1 ;;
    --with) shift; groups="$groups ${1:-}" ;;
  esac
  shift
done
os=linux; [ "$(uname)" = Darwin ] && os=mac
arch="$(uname -m)"
dest="$HOME/.claude/toolkit"; skills="$HOME/.claude/skills"
mkdir -p "$dest" "$skills"
ok=(); todo=(); failed=()
export PATH="$HOME/.local/bin:$PATH"

applies() {
  case "$1" in all) ;; mac) [ $os = mac ] || return 1 ;; mac-arm) [ $os = mac ] && [ "$arch" = arm64 ] || return 1 ;; *) return 1 ;; esac
  [[ " $groups " == *" $2 "* ]]
}
link() {  # $1 skill dir, $2 link path
  if [ -e "$2" ] && [ ! -L "$2" ]; then return 0; fi  # hand-installed copy: leave it
  [ $check = 1 ] && { [ -e "$2" ] || return 1; return 0; }
  ln -sfn "$1" "$2"
}
link_skills() {  # $1 repo dir, $2 comma list or empty
  local root="$1" only="${2:-}" n=0 missing=0
  for sk in "$root"/.claude/skills/*/ "$root"/skills/*/ "$root"/skills/*/*/; do
    [ -f "$sk/SKILL.md" ] || continue
    local nm; nm="$(basename "$sk")"
    if [ -n "$only" ] && [[ ",$only," != *",$nm,"* ]]; then continue; fi
    link "${sk%/}" "$skills/$nm" || missing=1; n=$((n + 1))
  done
  if [ $n = 0 ] && [ -f "$root/SKILL.md" ]; then link "$root" "$skills/$(basename "$root")" || missing=1; n=1; fi
  [ $n -gt 0 ] && [ $missing = 0 ]
}

# Skills we wrote ourselves.
[ -d "$here/skills" ] && link_skills "$here" "" && ok+=("own skills")

have_claude=0; command -v claude >/dev/null && have_claude=1
while read -r type name platform group rest; do
  [[ -z "${type:-}" || "$type" == \#* ]] && continue
  applies "$platform" "$group" || continue
  case "$type" in
    skills)
      read -r src only <<<"$rest"; only="${only#only=}"
      if [ ! -d "$dest/$name/.git" ]; then
        [ $check = 1 ] && { todo+=("$name"); continue; }
        git clone -q --depth 1 "$src" "$dest/$name" || { failed+=("$name (clone)"); continue; }
      elif [ $check = 0 ]; then
        git -C "$dest/$name" pull -q --ff-only || failed+=("$name (update)")
      fi
      if link_skills "$dest/$name" "$only"; then ok+=("$name"); else [ $check = 1 ] && todo+=("$name") || failed+=("$name (no SKILL.md)"); fi ;;
    plugin)
      [ $have_claude = 1 ] || { failed+=("$name (claude CLI not found)"); continue; }
      plug="${name%@*}"; mkt="${name#*@}"
      if claude plugin list 2>/dev/null | grep -q "$plug@$mkt"; then
        [ $check = 0 ] && claude plugin marketplace update "$mkt" >/dev/null 2>&1 && claude plugin update "$name" >/dev/null 2>&1
        ok+=("$name"); continue
      fi
      [ $check = 1 ] && { todo+=("$name"); continue; }
      claude plugin marketplace list 2>/dev/null | grep -q "$mkt" || claude plugin marketplace add "$rest" >/dev/null 2>&1
      if claude plugin install -s user "$name" >/dev/null 2>&1; then ok+=("$name"); else failed+=("$name"); fi ;;
    mcp)
      [ $have_claude = 1 ] || { failed+=("$name (claude CLI not found)"); continue; }
      if claude mcp get "$name" >/dev/null 2>&1; then ok+=("$name"); continue; fi
      [ $check = 1 ] && { todo+=("$name"); continue; }
      # shellcheck disable=SC2086
      if claude mcp add -s user "$name" -- $rest >/dev/null 2>&1; then ok+=("$name"); else failed+=("$name"); fi ;;
    cli)
      mgr="${rest%%:*}"; pkg="${rest#*:}"
      if command -v "$name" >/dev/null; then
        [ $check = 0 ] && [ "$mgr" = uv ] && uv tool upgrade -q "${pkg%%[*}" >/dev/null 2>&1
        ok+=("$name"); continue
      fi
      [ $check = 1 ] && { todo+=("$name"); continue; }
      case "$mgr" in
        brew) command -v brew >/dev/null && brew install -q "$pkg" >/dev/null 2>&1 && ok+=("$name") || failed+=("$name (needs Homebrew)") ;;
        uv)   command -v uv >/dev/null && uv tool install -q "$pkg" >/dev/null 2>&1 && ok+=("$name") || failed+=("$name (needs uv)") ;;
      esac ;;
  esac
done < "$here/manifest.txt"

echo "ready: ${ok[*]:-none}"
[ ${#todo[@]} -gt 0 ] && echo "missing (run install.sh): ${todo[*]}"
[ ${#failed[@]} -gt 0 ] && echo "FAILED: ${failed[*]}"
[ ${#failed[@]} -eq 0 ] && [ ${#todo[@]} -eq 0 ]
