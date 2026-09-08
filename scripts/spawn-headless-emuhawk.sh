#!/bin/sh
# Launches a separate, backgrounded EmuHawk instance for automated Lua captures - never the
# user's own live session (see the project's live-emulator-session rule). Uses
# config-headless.ini (all input bindings unbound, audio off - see that file's header) and
# prevents the window from ever taking focus, so it can't interrupt whatever the user is
# doing - including kicking a fullscreen app out of fullscreen, which merely minimizing the
# window after the fact can't prevent (the disruptive focus-steal already happened by the
# time any after-the-fact fix could react).
#
# The no-focus-steal mechanism is a KWin window rule (kwin-headless-rule.py), added right
# before launch and removed right after - it exists only for the lifetime of THIS spawned
# instance, so it never affects the user's own manual BizHawk launches (which happen when the
# rule isn't present at all). xdotool minimizing is kept as a redundant second layer.
#
# Usage: scripts/spawn-headless-emuhawk.sh <lua-script-path> [rom-path] [timeout-seconds]
#   lua-script-path   absolute path (BizHawk's --lua= doesn't resolve relative paths - see
#                     feedback-emuhawk-cli-lua-scripts / the project's EmuHawk CLI notes)
#   rom-path          defaults to the Suikoden I cue sheet used throughout this project
#   timeout-seconds   defaults to 120

set -u

BIZHAWK_DIR="/home/alex/Local/BizHawk-2.10-linux-x64"
CONFIG="/home/alex/Projects/Suikoden-Bizhawk-HUD/config-headless.ini"
DEFAULT_ROM="/mnt/Shared/ISOs/Suikoden/Suikoden (USA) (v1.1).cue"
KWIN_RULE_SCRIPT="/home/alex/Projects/Suikoden-Bizhawk-HUD/scripts/kwin-headless-rule.py"

LUA_SCRIPT="${1:?usage: spawn-headless-emuhawk.sh <lua-script-path> [rom-path] [timeout-seconds]}"
ROM="${2:-$DEFAULT_ROM}"
TIMEOUT="${3:-120}"

# Always remove the KWin rule on exit, however this script ends (success, timeout, Ctrl-C) -
# it must never be left in place after we're done, since a stale rule (however unlikely to
# survive) would be the "universal rule" behavior the user explicitly didn't want.
cleanup() {
  python3 "$KWIN_RULE_SCRIPT" remove >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

python3 "$KWIN_RULE_SCRIPT" add

cd "$BIZHAWK_DIR"
timeout "$TIMEOUT" ./EmuHawkMono.sh --config="$CONFIG" --lua="$LUA_SCRIPT" "$ROM" \
  > /tmp/spawn-headless-emuhawk-last.log 2>&1 &
BGPID=$!

# Redundant second layer: also explicitly minimize via xdotool as soon as the window(s)
# appear, in case the KWin rule ever fails to apply in time for some reason.
i=0
while [ "$i" -lt 100 ]; do
  ids="$(xdotool search --name "BizHawk" 2>/dev/null || true)"
  if [ -n "$ids" ]; then
    for id in $ids; do
      xdotool windowminimize "$id" 2>/dev/null || true
    done
    break
  fi
  i=$((i + 1))
  sleep 0.05
done
i=0
while [ "$i" -lt 40 ]; do
  ids="$(xdotool search --name "Lua Console" 2>/dev/null || true)"
  if [ -n "$ids" ]; then
    for id in $ids; do
      xdotool windowminimize "$id" 2>/dev/null || true
    done
    break
  fi
  i=$((i + 1))
  sleep 0.05
done

wait "$BGPID"
