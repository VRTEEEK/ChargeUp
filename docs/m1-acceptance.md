# Milestone 1 acceptance log

Status: **not yet run on devices.** This file records what has been verified and what still needs Mo and real hardware. Milestone 2 visuals do not start until the device section below is filled in.

## Verified without devices (12 Oct 2026)

| Check | How | Result |
|---|---|---|
| Sequence decodes; missing field, bad advance, bad ramp, duplicate id, missing countdown all fail | `swift test`, SequenceTests | pass (10 tests) |
| Reducer: happy path, one step per tap, connect ignored outside countdown, auto-advance at 400 ms, reset from every state, charge gated on presence | `swift test`, SessionReducerTests | pass (10 tests) |
| Codec round-trips every message; out-of-order and duplicate seq dropped; hello resets gate; ring buffer and CSV | `swift test`, MessageTests | pass (10 tests) |
| Two in-process channels over real Bonjour exchange hello and stepChanged; full seven-step run host to mirror | `swift test`, PeerChannelTests | pass (2 tests, ~3 s) |
| Vision app builds | `xcodebuild`, visionOS Simulator | pass |
| Companion app builds | `xcodebuild`, iOS Simulator | pass |
| Built Info.plists carry `_chargeup._tcp` / `_udp` and the local-network string | `plutil -p` on the built apps | pass |
| Real SessionHost (macOS process) + real SessionMirror (second macOS process) run START → … → DONE → RESET, CSV exported | throwaway CLI pair, not in repo | pass; connect round trip 0.7 ms on loopback |
| Vision operator window renders in visionOS 2.3 simulator | `simctl launch` + screenshot | pass |
| Immersive step label in simulator | needs a click in Simulator.app | **not verified** |
| Haptic pulse and ramp | needs an iPhone | **not verified** (no haptic hardware in simulator) |

Not possible on this Mac today: no iOS simulator runtime is installed in Xcode 27 beta, so the companion UI has only been compiled, not run.

## Device checks for Mo

Setup: Vision Pro, iPad (Nurse), iPhone (Haptic). Wi-Fi off on all three; iPad hosting a Personal Hotspot; Vision Pro and iPhone joined to it. Build and run each app from Xcode with your team selected (DEVELOPMENT_TEAM is blank in both projects). Accept the Local Network prompt on every device the first time.

1. **Pairing.** Open Charge Up on Vision Pro, tap Start. Open the companion on the iPad, pick Nurse. Within 5 s the badge should read "Linked to headset" and the Vision operator window should list `nurse`. Repeat with the iPhone as Haptic: green dot.
   - Look for: both companions linked, no restart needed. If a companion sits on "Looking for headset" past 10 s, note which device and whether killing and relaunching it helps.
2. **Three clean runs.** On the iPad tap START, then the button through all seven steps (Next, Next, CONNECT, [auto], NEEDLE OUT, Next, DONE), then RESET. Three times.
   - Look for: the Vision label and the iPad highlight always on the same step; the iPad button disabled during the 400 ms `connect` step; no step skipped or repeated when you tap twice quickly.
3. **Round trip.** After each CONNECT the iPad shows "Connect round trip N ms". Tap Export log at the end and AirDrop the CSV to your Mac.
   - Pass: every round trip under 100 ms. In the CSV, the `sent,connect` row and the following `received,stepChanged,connect` row differ by under 0.100 in `localTimestamp`.
4. **Haptics.** With the iPhone in hand: one sharp tap at CONNECT; a buzz that rises over about 4 s during `charge`; silence the instant you tap NEEDLE OUT; nothing on any other step; nothing after RESET.
   - Look for: the ramp is clearly rising, not flat, and stops cleanly rather than fading.
5. **Drop and rejoin.** Mid-session, force-quit the iPad app and reopen it as Nurse. It should rejoin and show the current step, not START.

Record results here, with the CSV filename, before starting Milestone 2.

## Results

_(empty)_
