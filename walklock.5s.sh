#!/bin/bash
# Uthereal Physical Security — WalkLock  |  https://uthereal.ai
# walklock.5s.sh — SwiftBar plugin: menu bar control for WalkLock.
# Filename's "5s" = refresh every 5 seconds. See README for install steps.

PATH=/usr/bin:/bin:/usr/sbin:/sbin
LABEL="com.uthereal.walklock"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
PAUSE="$HOME/.walklock-paused"
PAUSE_UNTIL="$HOME/.walklock-pause-until"
LOG="$HOME/Library/Logs/walklock.log"
SELF="$0"

# ---- click actions (menu items re-invoke this script with a flag) -----------
case "${1:-}" in
  --pause)    touch "$PAUSE"; rm -f "$PAUSE_UNTIL"; exit 0 ;;
  --pause1h)  touch "$PAUSE"; echo $(( $(date +%s) + 3600 )) > "$PAUSE_UNTIL"; exit 0 ;;
  --resume)   rm -f "$PAUSE" "$PAUSE_UNTIL"; exit 0 ;;
  --stop)     launchctl unload "$PLIST" 2>/dev/null; exit 0 ;;
  --start)    launchctl load "$PLIST" 2>/dev/null; exit 0 ;;
  --locknow)  pmset displaysleepnow; exit 0 ;;
esac

# ---- auto-resume if a timed pause has expired -------------------------------
if [ -f "$PAUSE_UNTIL" ]; then
  until=$(cat "$PAUSE_UNTIL" 2>/dev/null)
  if [ -n "$until" ] && [ "$(date +%s)" -ge "$until" ]; then
    rm -f "$PAUSE" "$PAUSE_UNTIL"
  fi
fi

# ---- read current state -----------------------------------------------------
loaded=false; launchctl list 2>/dev/null | grep -q "$LABEL" && loaded=true
paused=false; [ -f "$PAUSE" ] && paused=true

# ---- menu bar icon ----------------------------------------------------------
if   ! $loaded; then echo "🔓"        # stopped
elif $paused;   then echo "⏸"         # paused
else                 echo "🔒"        # armed
fi
echo "---"

# ---- dropdown ---------------------------------------------------------------
if $loaded; then
  if $paused; then
    if [ -f "$PAUSE_UNTIL" ]; then
      ts=$(date -r "$(cat "$PAUSE_UNTIL")" '+%H:%M' 2>/dev/null)
      echo "Paused until $ts | color=orange"
    else
      echo "Paused (indefinitely) | color=orange"
    fi
    echo "Resume locking | bash=\"$SELF\" param1=--resume terminal=false refresh=true"
  else
    echo "Armed — locks when you leave | color=green"
    echo "Pause locking | bash=\"$SELF\" param1=--pause terminal=false refresh=true"
    echo "Pause for 1 hour | bash=\"$SELF\" param1=--pause1h terminal=false refresh=true"
  fi
  echo "---"
  echo "Stop (unload agent) | bash=\"$SELF\" param1=--stop terminal=false refresh=true"
else
  echo "Stopped | color=red"
  echo "Start (load agent) | bash=\"$SELF\" param1=--start terminal=false refresh=true"
fi

echo "---"
echo "Lock now | bash=\"$SELF\" param1=--locknow terminal=false"
echo "View log | bash=/usr/bin/open param1=-a param2=Console param3=\"$LOG\" terminal=false"
echo "Refresh | refresh=true"
