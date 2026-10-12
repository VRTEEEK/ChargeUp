# Milestone 2 task 1 — forearm anchor device check

Hand tracking does not run in the simulator. This task is built, unit-tested on macOS, and otherwise unverified until the steps below are done on Vision Pro.

## What was built

- `ForearmAnchor` (Vision app, Tracking/) subscribes to `HandTrackingProvider.anchorUpdates`, picks the held hand by `HandAnchor.chirality`, and reads `HandSkeleton.JointName.forearmWrist` and `.forearmArm`. Names confirmed against Apple's `HandSkeleton.JointName` page (visionOS 1.0+) and the visionOS 27 SDK's ARKit Swift interface (cases 25 and 26 in `hand_skeleton.h`).
- `ForearmPoseSolver` (ChargeUpCore): port = wrist joint + 60 mm along the forearm toward the elbow + 25 mm along the wrist joint's dorsal axis. Port frame +Y is the skin normal, +X points at the hand.
- `ForearmTracker` (ChargeUpCore): one-euro smoothing; on tracking loss holds the last pose fully opaque for 2 s, then fades to 50 % over 300 ms; on re-acquire eases to the new pose over a few frames instead of snapping.
- A placeholder blue disc (`PortEntity`, 40 mm) sits at the solved pose. The Milestone 1 step label is gone from the immersive space; the operator window now shows a Forearm status line (tracked / holding / faded / unauthorized ...).
- All numbers are in `sequence.json` under `config.forearm`.

Apple does not document which local axis of the forearm joint points out of the back of the arm, so `config.forearm.dorsalAxis` ("+y" by default) is the one value this check exists to settle.

## Before you start

- Select your team in the ChargeUpVision project. First launch asks for hand tracking permission: allow it.
- Put a small sticker on your **left** forearm, on the back of the arm, 60 mm up from the wrist crease (config `heldArm` is `left`; change it to `right` if you want the other arm).
- Build and run on the headset, tap Start in the operator window.

## Checks

1. **Does the disc appear, and on which side?** Hold the left forearm in front of you, palm down, then turn it palm up.
   - Pass: the disc rides on the back of the forearm in both poses.
   - Disc on the palm side: set `dorsalAxis` to `"-y"`. Disc on the thumb or little-finger edge: try `"+z"` then `"-z"`. Rebuild (it is a JSON edit; no code change).
2. **Position against the sticker.** Palm down, arm resting on a table.
   - Pass: the disc centre is within about 10 mm of the sticker along the arm and sits on the skin, not sunk in or floating.
   - Too far from / close to the wrist: adjust `portOffsetProximalMm`. Floating or sunk: adjust `forearmRadiusMm`.
3. **Stillness jitter.** Rest the arm on the table for 10 s.
   - Pass: the disc does not visibly shimmer. If it does, lower `filterMinCutoffHz` (0.5).
4. **Lag on movement.** Lift the arm briskly 30 cm and stop.
   - Pass: the disc arrives within roughly one frame of the arm stopping, with no overshoot. If it trails visibly, raise `filterBeta` (4.0); if it jitters during motion, lower it (1.0).
5. **Occlusion by a helper's hand** (the point of this task). Second person wraps their hand around your wrist as a nurse would, holds 1 s, releases, then holds 5 s, releases.
   - Pass after a 1 s hold: the disc stays where it was, fully visible (operator window reads "holding"), then resumes without a jump.
   - Pass after a 5 s hold: the disc stays in place and dims to half at the 2 s mark (reads "faded"), then brightens and resumes without a jump when the hand is lifted.
   - Fail if the disc vanishes, teleports, or spins when tracking returns. Note which.
6. **Gaze away.** Look at the ceiling for 3 s, then back at the arm.
   - Note what happens; hand tracking usually stops when the hands leave the cameras' view, so expect "holding" then "faded" and a clean recovery.

## Record

| Check | Result | Value changed (if any) |
|---|---|---|
| 1 side | | dorsalAxis = |
| 2 position | | offsets = |
| 3 jitter | | |
| 4 lag | | |
| 5 occlusion 1 s / 5 s | | |
| 6 gaze away | | |

Paste the final `config.forearm` block here when done.
