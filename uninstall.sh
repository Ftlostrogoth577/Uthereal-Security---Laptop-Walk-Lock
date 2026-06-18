#!/bin/bash
# Uthereal Physical Security — WalkLock  |  https://uthereal.ai
# uninstall.sh — stop WalkLock and remove everything it created.

LABEL="com.uthereal.walklock"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
rm -f "$HOME/.walklock-paused" "$HOME/.walklock-pause-until"
rm -rf "$HOME/.cache/walklock"

echo "WalkLock uninstalled."
echo "If you added the menu bar plugin, remove walklock.5s.sh from your SwiftBar plugin folder."
