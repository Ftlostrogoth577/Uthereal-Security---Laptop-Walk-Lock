# Uthereal Physical Security — WalkLock

> Part of **Uthereal Physical Security**, a small suite of endpoint hardening tools.

Lock your Mac automatically when you walk away with your iPhone — no Apple Watch required.

## Why we built this

At Uthereal, privacy and security aren't features bolted on at the end — they're the foundation we build on. Our platform turns our customers' most sensitive proprietary content into AI systems they own outright, with zero data retention. Earning that trust means defending it at every layer.

That responsibility doesn't end with our software. It extends to the physical machines our engineers work on every day. An unlocked laptop is one of the oldest and most overlooked attack surfaces there is — a moment of inattention in a café, a coworking space, or a conference hall is all it takes to expose code, credentials, and customer data. WalkLock is the small, sharp tool we built so that moment never happens: the instant one of our engineers steps away from their laptop, it locks. No shortcut to remember, no discipline required — the security is automatic.

We're open-sourcing it because good security hygiene shouldn't be proprietary. Learn more about how we think about privacy and security at [uthereal.ai](https://uthereal.ai).

WalkLock watches your iPhone's Bluetooth signal strength. When the signal fades (you leave the desk) or disappears (you leave the room), it locks your Mac. When you come back, it stays unlocked for you to log in. It's a tiny CoreBluetooth helper plus a shell script — no kernel extensions, no account, no telemetry.

## How it works

macOS has no built-in "lock when my iPhone leaves" feature (the native proximity feature is Apple Watch only). WalkLock fills that gap the same way apps like BLEUnlock do: it scans for Bluetooth Low Energy advertisements, reads the RSSI (signal strength) of your phone, smooths it over a few readings, and compares it to a distance threshold. The Bluetooth part is a small compiled Swift helper (bash can't read RSSI); a shell script consumes its output and does the locking. That separation is the whole design.

## Requirements

- macOS 12 or later
- Xcode Command Line Tools (for the one-time compile): `xcode-select --install`
- An iPhone with Bluetooth on
- Optional: [SwiftBar](https://github.com/swiftbar/SwiftBar) for the menu bar control

## Quick start

```bash
git clone https://github.com/<you>/walklock.git
cd walklock
chmod +x walklock.sh install.sh uninstall.sh

# 1. Find your iPhone's Bluetooth ID
./walklock.sh scan

# 2. Run it (foreground, to test)
./walklock.sh <UUID-from-step-1>
```

Walk away — your Mac should lock after a few seconds. `Ctrl-C` to stop.

> **Note on privacy:** this repo ships with no device ID baked in. The UUID you discover is local to *your* Mac (CoreBluetooth assigns a per-Mac identifier; it is not your phone's hardware MAC address) and is only ever passed at runtime. Nothing personal is committed anywhere.

## Finding your iPhone's UUID

```bash
./walklock.sh scan
```

This scans for ~12 seconds and prints every nearby Bluetooth device as:

```
A1B2C3D4-5678-90AB-CDEF-1234567890AB   -41 dBm   —
71F0...                                 -88 dBm   AirPods
```

Identify your iPhone by **signal strength**: with the phone in your hand next to the Mac, yours is the **strongest** signal (the *least negative* dBm — e.g. `-41` is closer than `-80`). iPhones usually show no name (`—`) for privacy, so go by the number. Copy that UUID.

If your phone doesn't appear: unlock it, toggle its screen on, and re-run — an idle iPhone advertises only intermittently.

## Run automatically at login

```bash
./install.sh <your-UUID>
```

This de-quarantines the scripts, generates a `launchd` agent at `~/Library/LaunchAgents/com.uthereal.walklock.plist`, and starts it. It will now run at every login and restart itself if it ever crashes.

**Two one-time approvals are required:**

1. **Bluetooth permission.** The first time the helper runs under launchd, macOS prompts to allow Bluetooth. Approve it. (If you miss it: System Settings → Privacy & Security → Bluetooth.)
2. **Lock-on-sleep setting.** WalkLock locks by sleeping the display, so you must tell macOS to require a password then: System Settings → Lock Screen → **"Require password after screen saver begins or display is turned off" → Immediately**. Without this the screen sleeps but doesn't lock.

Check it's running:

```bash
launchctl list | grep walklock
tail -f ~/Library/Logs/walklock.log
```

## Menu bar control (optional)

For one-click pause/resume/stop, install the [SwiftBar](https://github.com/swiftbar/SwiftBar) plugin:

1. `brew install --cask swiftbar` (or download from the SwiftBar releases page).
2. Launch SwiftBar and choose a plugin folder when asked.
3. Copy `menubar/walklock.5s.sh` into that folder and `chmod +x` it.
4. SwiftBar → Refresh.

The icon shows state at a glance — 🔒 armed, ⏸ paused, 🔓 stopped — with a dropdown to pause (indefinitely or for one hour), stop/start the agent, or lock immediately.

## Controlling it from the command line

Without the menu bar, the same controls are plain files and commands:

```bash
touch ~/.walklock-paused     # pause (keeps monitoring, won't lock)
rm ~/.walklock-paused        # resume

# pause for one hour, auto-resume
touch ~/.walklock-paused; echo $(( $(date +%s) + 3600 )) > ~/.walklock-pause-until

# full stop / start (the real kill switch)
launchctl unload ~/Library/LaunchAgents/com.uthereal.walklock.plist
launchctl load   ~/Library/LaunchAgents/com.uthereal.walklock.plist
```

## Tuning

Edit the two values at the top of `walklock.sh`, then reload the agent
(`launchctl unload … && launchctl load …`):

| Setting     | Meaning                                          | Try if…                                  |
|-------------|--------------------------------------------------|------------------------------------------|
| `GRACE`     | Seconds out of range before locking (default 15) | Locks during stretches → raise to 30–45  |
| `THRESHOLD` | dBm distance cutoff (default -75)                | Locks too soon → lower to -85; too late → raise to -65 |

## Uninstall

```bash
./uninstall.sh
```

Removes the launchd agent, pause flags, and the build cache. If you added the
SwiftBar plugin, delete `walklock.5s.sh` from your plugin folder.

## Troubleshooting

- **`bad interpreter: Operation not permitted`** — the file is quarantined from download. Run `xattr -dr com.apple.quarantine .` in the repo folder (`install.sh` does this for you).
- **Screen sleeps but doesn't lock** — set the Lock Screen password requirement to *Immediately* (see above).
- **Never locks / `Bluetooth permission denied` in the log** — approve Bluetooth in System Settings → Privacy & Security → Bluetooth.
- **Locks while you're still sitting there** — Bluetooth signal fluctuates; raise `GRACE` and/or lower `THRESHOLD`.
- **Phone not found in scan** — wake/unlock the phone and re-run; idle iPhones advertise intermittently.

### Want the lock screen to appear instantly instead of via display-sleep?

Replace the `lock_screen` function in `walklock.sh` with:

```bash
lock_screen() { osascript -e 'tell application "System Events" to keystroke "q" using {control down, command down}'; }
```

This pops the lock screen immediately but needs Accessibility permission for the
process running it (System Settings → Privacy & Security → Accessibility).

## Credits

Built and maintained by [Uthereal](https://uthereal.ai). Bluetooth proximity approach adapted from [BLEUnlock](https://github.com/ts1/BLEUnlock) by Takeshi Sone (MIT).

## License

MIT — see [LICENSE](LICENSE).
