#!/bin/bash
# Uthereal Physical Security — WalkLock  |  https://uthereal.ai
# install.sh — set WalkLock to run automatically at login via launchd.
#
#   ./walklock.sh scan        # first, to find your iPhone's UUID
#   ./install.sh <UUID>       # then install with that UUID

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$DIR/walklock.sh"
LABEL="com.uthereal.walklock"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/walklock.log"

UUID="${1:-}"
if [ -z "$UUID" ]; then
  echo "Usage: ./install.sh <iPhone-UUID>"
  echo "Don't have it yet?  Run:  ./walklock.sh scan"
  exit 1
fi

# Clear macOS download quarantine and set exec bits on all scripts.
xattr -dr com.apple.quarantine "$DIR"/*.sh "$DIR"/menubar/*.sh 2>/dev/null || true
chmod +x "$SCRIPT" "$DIR"/menubar/*.sh 2>/dev/null || true

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SCRIPT</string>
        <string>$UUID</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>$LOG</string>
    <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo "Installed and started (label: $LABEL)."
echo
echo "Two one-time steps still needed:"
echo "  1. Approve the Bluetooth permission prompt when it appears."
echo "  2. System Settings > Lock Screen > 'Require password ... after display is"
echo "     turned off' = Immediately, so display-sleep actually locks."
echo
echo "Logs: tail -f $LOG"
