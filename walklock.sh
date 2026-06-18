#!/bin/bash
# Uthereal Physical Security — WalkLock  |  https://uthereal.ai
# walklock.sh — lock your Mac when your iPhone walks away (BLE proximity, no Apple Watch).
#
#   chmod +x walklock.sh
#   ./walklock.sh scan          # find your iPhone's UUID (phone in hand, recently unlocked)
#   ./walklock.sh <UUID>        # monitor + lock
#
# Tuning (top of file): THRESHOLD lower (e.g. -85) = must be farther to lock; GRACE = delay.
# Builds a small CoreBluetooth helper on first run and caches it in ~/.cache/walklock.

set -euo pipefail

# ---- config (or pass UUID as the first argument) ----------------------------
UUID="${1:-PUT-YOUR-IPHONE-UUID-HERE}"
THRESHOLD=-75
GRACE=15
PAUSE_FLAG="$HOME/.walklock-paused"        # if this file exists, don't lock
PAUSE_UNTIL="$HOME/.walklock-pause-until"  # epoch deadline for a timed pause
# -----------------------------------------------------------------------------

CACHE="$HOME/.cache/walklock"
SRC="$CACHE/proximity.swift"
BIN="$CACHE/proximity"
mkdir -p "$CACHE"

# Lock the screen. pmset sleeps the display; with "Require password immediately
# after screen saver/display off" set, that locks the Mac (no extra permission).
lock_screen() { pmset displaysleepnow; }

# ---- embedded Swift helper --------------------------------------------------
cat > "$SRC" <<'SWIFT'
// Minimal BLE RSSI proximity monitor. Approach adapted from BLEUnlock (MIT).
import Foundation
import CoreBluetooth
setvbuf(stdout, nil, _IONBF, 0)

func die(_ m: String) -> Never {
    FileHandle.standardError.write((m + "\n").data(using: .utf8)!); exit(2)
}
func argValue(_ f: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: f), i + 1 < a.count else { return nil }
    return a[i + 1]
}

let scanMode  = CommandLine.arguments.contains("--scan")
let verbose   = CommandLine.arguments.contains("--verbose")
let targetStr = argValue("--monitor")
let threshold = Int(argValue("--threshold") ?? "-75") ?? -75
let window    = Int(argValue("--window") ?? "6") ?? 6
let grace     = Double(argValue("--grace") ?? "15") ?? 15

if !scanMode && targetStr == nil {
    die("usage: proximity --scan | --monitor <UUID> [--threshold n] [--grace s]")
}
let targetUUID = targetStr.flatMap { UUID(uuidString: $0) }
if !scanMode && targetUUID == nil { die("invalid UUID") }

final class Monitor: NSObject, CBCentralManagerDelegate {
    var central: CBCentralManager!
    var samples: [Int] = []
    var lastSeen = Date.distantPast
    var awaySince: Date? = nil
    var state = "UNKNOWN"
    var seen = Set<UUID>()

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
        if !scanMode {
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        }
    }
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn:
            c.scanForPeripherals(withServices: nil,
                                 options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        case .unauthorized:
            die("Bluetooth permission denied — System Settings > Privacy & Security > Bluetooth")
        case .poweredOff: die("Bluetooth is off")
        default: break
        }
    }
    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData ad: [String: Any], rssi RSSI: NSNumber) {
        let rssi = min(RSSI.intValue, 0)
        if rssi >= 0 { return }
        if scanMode {
            guard !seen.contains(p.identifier) else { return }
            seen.insert(p.identifier)
            let name = p.name ?? (ad[CBAdvertisementDataLocalNameKey] as? String) ?? "—"
            print("\(p.identifier)   \(rssi) dBm   \(name)")
            return
        }
        guard p.identifier == targetUUID else { return }
        lastSeen = Date()
        samples.append(rssi); if samples.count > window { samples.removeFirst() }
        let avg = samples.reduce(0, +) / samples.count
        if verbose { print("RSSI \(avg)") }
        if avg >= threshold { awaySince = nil; transition("NEAR") }
        else if awaySince == nil { awaySince = Date() }
    }
    func tick() {
        let now = Date()
        let lost = now.timeIntervalSince(lastSeen) > grace
        let faded = (awaySince.map { now.timeIntervalSince($0) > grace } ?? false)
        if lost || faded { transition("AWAY") }
    }
    func transition(_ s: String) {
        guard s != state else { return }
        state = s; print("STATE \(s)")
    }
}
let m = Monitor()
RunLoop.main.run()
SWIFT
# -----------------------------------------------------------------------------

# Compile if missing or source changed.
if [ ! -x "$BIN" ] || [ "$SRC" -nt "$BIN" ]; then
  echo "Building proximity helper…" >&2
  if ! command -v swiftc >/dev/null 2>&1; then
    echo "swiftc not found — install Xcode command line tools: xcode-select --install" >&2
    exit 1
  fi
  swiftc "$SRC" -o "$BIN" -framework CoreBluetooth
  codesign --force --sign - "$BIN" 2>/dev/null || true
fi

# Scan mode: list nearby devices so you can grab your iPhone's UUID.
if [ "${1:-}" = "scan" ] || [ "${1:-}" = "--scan" ]; then
  echo "Scanning 12s — your iPhone is usually the strongest (least negative) signal:" >&2
  ( "$BIN" --scan & p=$!; sleep 12; kill "$p" 2>/dev/null ) || true
  exit 0
fi

if [ "$UUID" = "PUT-YOUR-IPHONE-UUID-HERE" ]; then
  echo "No UUID set. Run:  ./walklock.sh scan   then:  ./walklock.sh <UUID>" >&2
  exit 1
fi

echo "Monitoring $UUID (threshold ${THRESHOLD}dBm, grace ${GRACE}s). Ctrl-C to stop." >&2
while true; do
  "$BIN" --monitor "$UUID" --threshold "$THRESHOLD" --grace "$GRACE" | while read -r line; do
    case "$line" in
      "STATE AWAY")
        if [ -f "$PAUSE_FLAG" ]; then
          # auto-clear an expired timed pause, then lock
          if [ -f "$PAUSE_UNTIL" ] && [ "$(date +%s)" -ge "$(cat "$PAUSE_UNTIL" 2>/dev/null || echo 0)" ]; then
            rm -f "$PAUSE_FLAG" "$PAUSE_UNTIL"
            echo "$(date '+%H:%M:%S') pause expired — locking" >&2; lock_screen
          else
            echo "$(date '+%H:%M:%S') away — paused, not locking" >&2
          fi
        else
          echo "$(date '+%H:%M:%S') away — locking" >&2; lock_screen
        fi
        ;;
      "STATE NEAR") echo "$(date '+%H:%M:%S') back at desk" >&2 ;;
    esac
  done
  echo "helper exited, restarting in 3s…" >&2
  sleep 3
done
