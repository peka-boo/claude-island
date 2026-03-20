#!/bin/bash
# hook-sender.sh — Forwards Claude Code hook events to Claude Island
# version: 1
#
# Exit instantly if the desktop app server isn't reachable
curl -s --connect-timeout 0.3 "http://localhost:__PORT__/health" >/dev/null 2>&1 || exit 0

# Read hook JSON from stdin
INPUT=$(cat 2>/dev/null || echo '{}')

# Extract event name
EVENT_NAME=$(echo "$INPUT" | grep -o '"hook_event_name":"[^"]*"' | head -1 | cut -d'"' -f4)

# Walk up process tree to find terminal app PID and shell PID
TERM_PID=""
LAST_SHELL=""
SHELL_PID=""
CUR=$$
while [ "$CUR" != "1" ] && [ -n "$CUR" ]; do
  PAR=$(ps -o ppid= -p "$CUR" 2>/dev/null | tr -d ' ')
  [ -z "$PAR" ] && break
  COMM=$(ps -o comm= -p "$PAR" 2>/dev/null); COMM="${COMM##*/}"
  case "$COMM" in
    zsh|bash|fish|sh|nu|pwsh|elvish|-zsh|-bash|-fish|-sh) LAST_SHELL="$PAR" ;;
    Terminal|iTerm2|wezterm-gui|kitty|Cursor|Code|Windsurf|ghostty|alacritty|Warp|Zed|pycharm|idea|webstorm|goland|clion|phpstorm|rubymine|rider) TERM_PID="$PAR"; SHELL_PID="$LAST_SHELL"; break ;;
  esac
  CUR="$PAR"
done

# Inject terminal_pid and shell_pid into JSON payload
if [ -n "$TERM_PID" ]; then
  INJECT="\"terminal_pid\":$TERM_PID"
  [ -n "$SHELL_PID" ] && INJECT="$INJECT,\"shell_pid\":$SHELL_PID"
  INPUT=$(echo "$INPUT" | sed "s/}$/,$INJECT}/")
fi

if [ "$EVENT_NAME" = "PermissionRequest" ]; then
    # Blocking: wait for user decision in the app
    TMPFILE=$(mktemp /tmp/claude-island-hook.XXXXXX)
    curl -s -w "\n%{http_code}" -X POST \
      -H "Content-Type: application/json" -d "$INPUT" \
      "http://localhost:__PORT__/hook" \
      --connect-timeout 2 >"$TMPFILE" 2>/dev/null &
    CURL_PID=$!
    trap 'kill $CURL_PID 2>/dev/null; rm -f "$TMPFILE"; exit 0' TERM HUP INT
    wait $CURL_PID
    RESPONSE=$(cat "$TMPFILE")
    rm -f "$TMPFILE"
    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    [ -n "$BODY" ] && echo "$BODY"
    [ "$HTTP_CODE" = "403" ] && exit 2
    exit 0
else
    # Fire-and-forget for all other events
    curl -s -X POST -H "Content-Type: application/json" -d "$INPUT" \
      "http://localhost:__PORT__/hook" \
      --connect-timeout 1 --max-time 2 2>/dev/null || true
    exit 0
fi
