# Charge Up — Build Brief for Claude Code

Working instructions for building the ARR hackathon prototype.
12 Oct 2026 · @Mo

## What we are building

Charge Up is a two-device prototype for the Asymmetric Reframed Reality hackathon (Goldsmiths/KCL, 4 to 6 November 2026), built for children on long-term chemotherapy. A child wearing Apple Vision Pro in passthrough sits through a day-care session: the port needle goes in, the line is flushed, a long infusion runs, and at the end the port is de-accessed. The nurse, with no headset, runs the session from an iPad with one button. The child sees the real nurse and parent, but their own access site, the needle and the near space are replaced by a charging scene: the infusion is energy flowing into a lantern, not a drug going in. Each session charges one lantern, and the lantern persists: every session adds a lit lantern to a sky the child sees again next time. A phone in the child's free hand plays a rising haptic ramp at the needle moment.

The hackathon version is a fixed seven-step sequence, one charging object, one scene. The demo is on a seated adult volunteer with a judge playing the nurse. Deadline for a working end-to-end demo: 3 November, before the event.

Design rules that override any implementation convenience:

1. **Honest, not hidden.** Nothing in the child's view pretends the needle is not happening. Each real sensation has exactly one visible counterpart, at the same place on the access site, at the same instant.
2. **Human-timed sync.** The needle moment fires only when the nurse taps Connect. Never infer it from sensors, timers or animation length.
3. **Stillness and attention are required only at the needle moment.** During the infusion the child is free to move, rest or sleep; the lantern charges on its own time and invites the child back rather than holding them.
4. **No text, no controllers, no menus in the child's view.** One gesture: hold still.
5. **Congruency map is data.** Every visual, sound and haptic belongs to a row in the sequence JSON. If it has no row, it does not ship.

## Platforms and decisions already made

Do not re-open these. They were chosen for a 48-hour build with one developer.

| Decision | Choice | Why |
|---|---|---|
| Child device | Apple Vision Pro, visionOS 2+, Swift, SwiftUI, RealityKit, ARKit | Passthrough quality allows partial replacement; keeps nurse's face real |
| Immersion style | ImmersiveSpace, `.mixed`, with `upperLimbVisibility(.hidden)` | Lets virtual geometry occlude the child's real arm where we draw over it |
| Forearm anchor | ARKit `HandTrackingProvider`, `forearmWrist` and `forearmArm` joints of the held arm | Only tracked joints available on the forearm; no markers needed |
| Attention proxy | Head pose from `WorldTrackingProvider` device anchor, angle to the port | Third-party apps cannot read gaze on visionOS; head direction is the honest substitute |
| Stillness | Wrist joint velocity over a 300 ms window, threshold in config | Drives charge progress; no extra sensor |
| Nurse and parent device | One iOS companion app (iPad and iPhone), SwiftUI, role picker on launch: Nurse, Parent, Haptic | Native needed for Multipeer and Core Haptics; one target, three roles |
| Sync channel | MultipeerConnectivity, visionOS hosts, companions browse; messages as Codable JSON | Peer-to-peer; works on a hotspot or with no infrastructure Wi-Fi |
| Haptics | iPhone in Haptic role, Core Haptics continuous event with intensity envelope 0.2 to 1.0 over the injection | Only Apple device with a true intensity ramp; Watch presets cannot ramp |
| Audio | One spatial `AudioFileResource` at the port entity | Sound confirms touch location |
| Fallback | Meta Quest 3, Unity 6, passthrough; same JSON sequence and message schema | Built only after Milestone 2 passes, in a separate folder |

visionOS realities to design around: no gaze data, no per-region passthrough masking (we occlude by drawing opaque geometry), hand tracking drops when the nurse's hand covers the child's wrist, and Multipeer discovery can take 2 to 5 s. Each of these has a task below.

## Repository layout

One Xcode workspace, one Swift package shared by both apps. Create this structure first and commit it empty.

```
ChargeUp/
  ChargeUp.xcworkspace
  Packages/ChargeUpCore/          # Swift package, no UI
    Sources/ChargeUpCore/
      Sequence.swift              # Step, Sequence, loaded from JSON
      Messages.swift              # Codable envelope for every peer message
      SessionState.swift          # state machine: idle -> step N -> complete
      PeerChannel.swift           # MultipeerConnectivity wrapper, host + browser
    Resources/sequence.json       # the congruency map (next section)
    Tests/                        # state machine + codec tests
  Apps/ChargeUpVision/            # visionOS target
    App/                          # entry, ImmersiveSpace, settings
    Tracking/                     # ForearmAnchor, AttentionProxy, StillnessMonitor
    Scene/                        # PortEntity, ChargeObjectEntity, EnergyFlow, StepVisuals
    Audio/
    Assets/                       # Reality Composer Pro package
  Apps/ChargeUpCompanion/         # iOS target: Nurse, Parent, Haptic roles
    Nurse/                        # step list + Connect button + presence indicators
    Parent/                       # mirrored step view + prompt text
    Haptic/                       # Core Haptics ramp player
  Fallback/ChargeUpQuest/         # Unity project, only after Milestone 2
  docs/
    sequence.md                   # human-readable congruency map
    demo-runbook.md               # step-by-step for demo day
```

Shared model, in ChargeUpCore. Keep it this small.

- `Step`: id, name, clinicalCue, perceived, haptic (none, pulse, ramp), audio, childAction, advance (nurseTap or auto with durationMs).
- `Message`: enum with associated values, all Codable: hello(role), stepChanged(stepId, hostTimestamp), connect(nurseTimestamp), presence(headOnPort: Bool, armStill: Bool, charge: Double), reset. Every message carries a monotonic sequence number; receivers drop out-of-order messages.
- `SessionState`: pure function (state, event) -> state. No RealityKit, no UIKit, so it is testable on macOS.

All three apps load the same sequence.json from the package bundle. Changing a step's visuals or timing is a JSON edit, not a code change.

## The sequence as data

This is the congruency map from the proposal, encoded. It is the source of truth; the proposal table is derived from it. It lives at `Packages/ChargeUpCore/Resources/sequence.json`.

```json
{
  "version": 1,
  "object": "lantern",
  "steps": [
    { "id": "hold",     "name": "Nurse holds the arm",
      "clinicalCue": "Firm grip, warmth",
      "perceived": "Guide places the charging port on the forearm",
      "childAction": "Offer the arm",
      "haptic": "none", "audio": "port_place",
      "advance": { "kind": "nurseTap" } },
    { "id": "swab",     "name": "Alcohol swab",
      "clinicalCue": "Cold, wet, brief",
      "perceived": "Port is cooled and polished; frost shimmer",
      "childAction": "Watch the port glow",
      "haptic": "none", "audio": "frost",
      "advance": { "kind": "nurseTap" } },
    { "id": "countdown", "name": "Pause before needle",
      "clinicalCue": "Nurse says: three, two, one",
      "perceived": "Three pulses of light at the port, 800 ms apart",
      "childAction": "Take a breath",
      "haptic": "none", "audio": "pulse",
      "advance": { "kind": "nurseTap", "label": "CONNECT" } },
    { "id": "connect",  "name": "Needle contact",
      "clinicalCue": "Sharp onset",
      "perceived": "Cable clicks into the port",
      "childAction": "Look at the port",
      "haptic": "pulse", "audio": "click",
      "advance": { "kind": "auto", "durationMs": 400 } },
    { "id": "charge",   "name": "Injection",
      "clinicalCue": "Pressure, spreading ache, 3 to 5 s",
      "perceived": "Energy bar fills; lantern brightens; flow only while arm is still and head is on port",
      "childAction": "Stay still so the flow continues",
      "haptic": "ramp", "audio": "flow_loop",
      "advance": { "kind": "nurseTap", "label": "NEEDLE OUT" } },
    { "id": "release",  "name": "Needle out",
      "clinicalCue": "Release",
      "perceived": "Cable disconnects; lantern fully lit",
      "childAction": "Exhale",
      "haptic": "none", "audio": "complete",
      "advance": { "kind": "nurseTap" } },
    { "id": "seal",     "name": "Cotton and plaster",
      "clinicalCue": "Pressure, adhesive",
      "perceived": "Seal placed over the port; charge mark remains on the arm",
      "childAction": "Look at the mark",
      "haptic": "none", "audio": "seal",
      "advance": { "kind": "nurseTap", "label": "DONE" } }
  ],
  "config": {
    "stillnessThresholdMps": 0.05,
    "stillnessWindowMs": 300,
    "headOnPortDegrees": 25,
    "chargeRatePerSecond": 0.25,
    "rampIntensity": [0.2, 1.0],
    "rampSharpness": 0.3
  }
}
```

Rules for this file: the nurse app renders its button label from `advance.label`; the Vision app renders visuals by step id; the haptic app only reacts to the `haptic` field. Nobody hardcodes a step.

## Milestone 1: plumbing (target 19 October)

Goal: two devices advance through all seven steps together, with haptics, and no visuals yet. Do this first and do it boring.

1. Create the workspace, the ChargeUpCore package and both app targets. Bundle IDs under the same team; enable Local Network and Bonjour (`_chargeup._tcp`) entitlements on both apps.
2. Implement `Sequence` loading from sequence.json with a decode test that fails loudly on a bad file.
3. Implement `SessionState` as a pure reducer with unit tests covering: every nurseTap advances exactly one step, auto steps advance after durationMs, connect is ignored unless the current step is countdown, reset from any state.
4. Implement `PeerChannel`. visionOS advertises and hosts; the companion browses and joins with its role in the hello message. Reconnect automatically on drop. Log every send and receive with hostTimestamp to a ring buffer the nurse app can export as CSV.
5. Nurse role: a vertical list of the seven steps with the current one highlighted, a single large button whose label comes from `advance.label` (default Next), and two indicators fed by presence messages: Head on port, Arm still. Button sends connect when the step is countdown, otherwise stepChanged.
6. Haptic role: on stepChanged to connect, play one transient pulse; on charge, start a Core Haptics continuous event with the intensity envelope from config; on release or reset, stop. Keep the screen on and show only a large green/red connection dot.
7. Vision app, placeholder: a floating text label showing the current step name in the ImmersiveSpace, so the chain is visible end to end.

Acceptance: with Wi-Fi off and the iPad on a hotspot, tap through all seven steps three times with no desync; the exported log shows connect-to-stepChanged round trip under 100 ms; haptic ramp audible/feelable for the full charge step and stops cleanly.

## Milestone 2: the child's experience (target 31 October)

Goal: the full reframed scene on Vision Pro, driven by the nurse's taps.

1. `ForearmAnchor`: subscribe to `HandTrackingProvider`; pick the held arm from config (default left). Build a transform from forearmWrist toward forearmArm and anchor a `PortEntity` 60 mm proximal to the wrist on the dorsal side. Smooth with a one-euro filter. When tracking drops (nurse's hand occludes), hold the last pose for up to 2 s, then fade the port to 50 percent instead of snapping it away. Never jump.
2. Arm replacement: a soft-edged opaque sleeve mesh around the forearm, textured to match the charging world, with `upperLimbVisibility(.hidden)` so it draws over the real arm. Keep the real hand visible beyond the wrist; replacing the hand breaks presence.
3. `StillnessMonitor`: wrist joint speed over a 300 ms window versus stillnessThresholdMps. Publish armStill in presence messages at 10 Hz.
4. `AttentionProxy`: angle between the device forward vector and the vector to the port versus headOnPortDegrees. Publish headOnPort. Do not use eye data; it is not available.
5. Step visuals, one function per step id, all in `StepVisuals`: hold places the port with a soft landing animation; swab runs a frost shimmer shader on the port; countdown pulses the port light three times at 800 ms; connect snaps a cable entity from the ChargeObject into the port with a click; charge advances a fill value at chargeRatePerSecond only while armStill and headOnPort are both true, drives the energy flow particles along the cable and the lantern's emissive strength; release retracts the cable and holds the lantern at full; seal fades a glowing mark onto the sleeve at the port position and keeps it after the port is removed.
6. `ChargeObject`: a lantern, placed 40 cm in front of the child at chest height, world-anchored at session start so it does not follow the head. Three states: dark, charging, lit.
7. Audio: one spatial source at the port for all per-step sounds, one at the lantern for the flow loop. Volumes in config.
8. Session flow: app opens in a plain window with one Start button for the operator; Start opens the ImmersiveSpace and begins advertising; a long pinch (2 s) anywhere resets, for the operator only.

Acceptance: a seated adult can run the full sequence with a second person holding their arm and tapping the iPad; the port stays on the forearm through the hold step with the helper's hand over the wrist; the charge bar visibly pauses when the arm moves or the head turns away and resumes when still; total session from Start to seal under two minutes.

## Milestone 3: demo hardening (3 November, then on site 5 to 6 November)

Goal: survives a judge, a hotspot and a tired operator.

1. Parent role: mirrors the nurse's step list without the button, plus a prompt line per step from a `prompts` array added to sequence.json (for example, charge: "Keep looking at the light, it's filling up"). Large type, readable at arm's length.
2. Rehearsal mode: a toggle on the nurse app that auto-advances every step on a timer so one person can test the Vision scene alone.
3. Recording: the Vision app writes a per-session CSV (step, hostTimestamp, armStill, headOnPort, charge) to Documents, retrievable over Files. This is the evidence for the evaluation section of the pitch.
4. Resilience: if the companion disconnects mid-session, the Vision app shows the operator a small reconnecting indicator outside the child's main view and holds the current step; on reconnect the companion receives the current state, not a reset.
5. Operator safety: nothing in the child's view can be triggered by the child; all control is on the iPad or the operator's long pinch.
6. Write `docs/demo-runbook.md`: power order, pairing steps, hotspot name, what to do on each failure, the 90-second script for the judge who plays the nurse.
7. Only now, if time allows, port the scene to Quest 3 in `Fallback/ChargeUpQuest` using the same sequence.json and message schema over a WebSocket bridge.

Acceptance: three consecutive clean runs from cold start, each started by a different person following only the runbook.

## Working rules and testing

How to work with me on this repo:

- Build in the milestone order above. Do not start Milestone 2 visuals until the Milestone 1 acceptance log exists in docs/.
- Before writing any RealityKit or ARKit code, check the current visionOS API names against Apple's documentation; several hand-tracking and immersion APIs changed between visionOS 1 and 2. Say which version you targeted.
- One pull request per numbered task. Each PR description states the task number, what was tested on a real device, and what was only tested in the simulator. Hand tracking and passthrough do not work in the simulator, so say so rather than claiming a pass.
- Ask me before adding any dependency outside Apple frameworks. The expected answer is no.
- Config values live in sequence.json or a Config.swift that reads it. No magic numbers in Tracking or Scene.
- Keep the child's scene free of UI. If you need a debug overlay, gate it behind a flag that defaults off and renders only in the operator window.
- When a task is blocked by hardware I need to test, stop and tell me exactly what to run and what to look for; do not stub the result as passing.

Tests that must exist and pass in CI (macOS, `swift test` on ChargeUpCore):

- Sequence decodes the shipped JSON; a missing field fails.
- SessionState reducer: full happy path, out-of-order connect ignored, reset from every state, auto-advance timing.
- Message codec round-trips every case, and out-of-order sequence numbers are dropped.
- PeerChannel: a loopback test with two in-process instances exchanging hello and stepChanged.

Device checks I will run myself, in this order, with your checklist: forearm anchor stability with a second person's hand over the wrist; port position accuracy against a sticker on the real arm; haptic ramp feel; end-to-end latency from iPad tap to cable click.

## Out of scope for this build

Do not build any of these, even if they seem small. They belong to the post-hackathon version.

- Child-size headset fit, calibration flows, or onboarding screens
- Clinical data logging beyond the per-session CSV
- Accounts, cloud sync, analytics, crash reporting
- Voice, speech or AI-driven content of any kind
- Any visual that does not map to a row in sequence.json
- Cloud sync of the lantern sky; the headset is the only store for now
- The end-of-treatment rising ceremony
