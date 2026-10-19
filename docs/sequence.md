# Charge Up — the sequence as the apps see it

Derived from `Packages/ChargeUpCore/Resources/sequence.json`. That file is the source of truth; if this table and the JSON disagree, the JSON wins and this file is stale.

| # | id | Nurse sees | Child feels (clinical cue) | Child sees (perceived) | Child does | Haptic phone | Sound | Advance |
|---|---|---|---|---|---|---|---|---|
| 1 | `cream` | Numbing cream on the port | Cool cream, cling film, a long wait | The port glow grows under the skin | Let it work | none | `port_place` at port | nurse tap (Next) |
| 2 | `clean` | Skin cleaned | Cold, wet, brief | Port polished; frost shimmer | Watch the port shine | none | `frost` at port | nurse tap (Next) |
| 3 | `countdown` | Count of three | Nurse says: three, two, one | Three pulses of light at the port, 800 ms apart | Take a breath, hold still | none | `pulse` at port | nurse tap (**CONNECT**) |
| 4 | `connect` | Port needle in | Sharp push, then pressure | Cable clicks into the port | Look at the port, hold still | ramp 0.2 → 1.0 over rampDurationMs, then stops | `click` at port | auto, 400 ms |
| 5 | `flush` | Flush and blood draw | Cold in the chest, a strange taste | The first spark runs up the cable and the lantern wakes | Watch the spark | none | `spark` at port | nurse tap (Next) |
| 6 | `charge` | Infusion | Hours on the pump; free to move, rest or sleep | The lantern fills over time | Come back and look whenever you like | none | `flow_loop` at lantern | nurse tap (**NEEDLE OUT**) |
| 7 | `release` | Needle out and dressing | Pull, pressure, adhesive | Cable disconnects; lantern fully lit and rises to join the sky; a charge mark fades onto the dressing | Watch it rise | none | `complete` at port | nurse tap (**DONE**) |

Stillness and attention are asked for at steps 3 and 4 only. The reducer's two gates are unchanged: `connect` is honoured only on `countdown`, and the fill lives on `charge`.

## Config

| Key | Value | Used by |
|---|---|---|
| `stillnessThresholdMps` | 0.05 | Vision, StillnessMonitor (M2); matters at the needle moment |
| `stillnessWindowMs` | 300 | Vision, StillnessMonitor (M2) |
| `headOnPortDegrees` | 25 | Vision, AttentionProxy (M2) |
| `sky.seededSessions` | 6 | Vision: fake past sessions written to sessions.json on first launch so the demo sky is not empty; Reset Sky re-seeds |
| `sky.riseSeconds` | 3 | Vision: the current lantern's rise into the cluster at release |
| `sky.clusterHeightM`, `clusterBehindM`, `clusterSpreadM`, `smallScale` | 0.55, 0.35, 0.7, 0.4 | Vision: where past lanterns sit relative to the current one, and how small they are |
| `charge.gatedByPresence` | false | SessionReducer: when true the fill only advances while armStill and headOnPort (the old rule) |
| `charge.demoDurationSec` | 90 | SessionReducer: seconds for the fill to go 0 to 1; a real infusion is hours, the demo compresses it |
| `charge.glanceDegrees`, `charge.glanceSeconds` | 20, 2.5 | Vision: a head turn toward the lantern during charge brightens it briefly, then it settles |
| `rampIntensity` | [0.2, 1.0] | Haptic role: start and end intensity of the continuous event |
| `rampSharpness` | 0.3 | Haptic role: sharpness of the continuous event |
| `rampDurationMs` | 4000 | Haptic role: length of the ramp that starts at `connect`; it ends on its own |
| `visuals.*` | see sequence.json | StepVisuals timings: creamGlowMs, countdownPulseCount/Ms, cableSnapMs, flushSparkMs, cableRetractMs, markFadeMs, flow packets, frost sparkles |
| `forearm.heldArm` | left | Vision, ForearmAnchor: which hand anchor to follow |
| `forearm.portOffsetProximalMm` | 60 | ForearmPoseSolver: wrist joint to port, toward the elbow |
| `forearm.forearmRadiusMm` | 25 | ForearmPoseSolver: bone line to skin |
| `forearm.dorsalAxis` | +y | ForearmPoseSolver: wrist joint axis that points out of the back of the arm (verify on device) |
| `forearm.holdLastPoseMs` | 2000 | ForearmTracker: hold the last pose this long after tracking drops |
| `forearm.occludedOpacity` | 0.5 | ForearmTracker: opacity after the hold expires |
| `forearm.fadeMs` | 300 | ForearmTracker: fade duration |
| `forearm.filterMinCutoffHz`, `filterBeta`, `filterDerivativeCutoffHz` | 1.0, 2.0, 1.0 | One-euro filter |
| `forearm.filterMaxStepMs` | 100 | Longest gap the filter integrates; re-acquired poses ease in over a few frames |

## Who owns what

- **Headset (`vision` role)** hosts the session. It runs the reducer and a 10 Hz tick, broadcasts `stepChanged` on every phase change, `presence` on every tick, and hands a newly joined companion the current step.
- **Nurse** sends `stepChanged(next step)` as a request, or `connect` on the countdown step, or `reset`. The host only honours a request for the step immediately after the current one, so a double tap cannot skip.
- **Haptic** reacts only to each step's `haptic` field: `pulse` taps once, `ramp` runs for `rampDurationMs` and ends on its own, `none` does nothing (so the ramp started at the needle moment is not cut off). Idle and complete stop it.
- **Parent** mirrors the step list. The prompt line is Milestone 3.

Reserved step ids in `stepChanged` that are not rows: `idle`, `complete`.

The lantern sky lives only in `Documents/sessions.json` on the headset (one record per completed session: date, variant, fill reached, seeded flag). The record is written when `release` is entered.

## Wire format

Every message is one JSON envelope sent reliably over MultipeerConnectivity (service `_chargeup._tcp`):

```json
{"seq": 12, "message": {"type": "stepChanged", "stepId": "charge", "hostTimestamp": 1791815136.08}}
```

Types: `hello{role}`, `stepChanged{stepId, hostTimestamp}`, `connect{nurseTimestamp}`, `presence{headOnPort, armStill, charge}`, `reset{}`, `skyState{sessions: [{date (ISO 8601), variant, fill, seeded}]}`. The headset sends `skyState` to a companion when it joins and after every release. `seq` is monotonic per sender; receivers drop anything not greater than the last accepted `seq` from that sender. A `hello` always resets the gate for its sender.
