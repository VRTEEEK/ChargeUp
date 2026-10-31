# ChargeUpMacNurse

For automated and scripted runs only. To be the nurse on a Mac, use the **Charge Up Nurse** app (the companion app's macOS destination, in /Applications and the Dock), which has the same keys and a window you can also use with the mouse.

It is the same `SessionMirror` and `PeerChannel` the companion uses, in a terminal.

## Launch

Put the Mac on the same Wi-Fi or hotspot as the headset, start Charge Up on the headset and tap Start, then:

```bash
cd Tools/ChargeUpMacNurse && swift run -c release
```

The first run builds it (about 10 s). It browses for `_chargeup._tcp`, links as the nurse, and prints the current step, the two presence indicators when they change, and the connect round trip after CONNECT. If macOS asks to allow the terminal on the local network, allow it.

## Keys

| Key | Does |
|---|---|
| space | the nurse button: START, Next, NEEDLE OUT, DONE, RESET |
| return | CONNECT, only on the countdown step |
| r | reset |
| k | reset sky: clears the headset's saved lanterns back to the seeded set |
| q or ctrl-c | quit; writes the message log to `~/Documents/chargeup-macnurse-<date>.csv` |

The CSV has the same columns as the iPad's Export log (localTimestamp, direction, peer, seq, type, stepId, hostTimestamp), so the Milestone 1 round-trip check reads the same way: the `sent,connect` row and the next `received,stepChanged,connect` row.

Verified 26 Oct 2026 against the Vision app in the visionOS 2.3 simulator: linked in under a second, full seven-step chain, connect round trip 1.5 ms on this Mac, 326-entry CSV. Not yet run against a Vision Pro.
