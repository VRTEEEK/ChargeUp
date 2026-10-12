# Charge Up — the sequence as the apps see it

Derived from `Packages/ChargeUpCore/Resources/sequence.json`. That file is the source of truth; if this table and the JSON disagree, the JSON wins and this file is stale.

| # | id | Nurse sees | Child feels (clinical cue) | Child sees (perceived) | Child does | Haptic phone | Sound at port | Advance |
|---|---|---|---|---|---|---|---|---|
| 1 | `hold` | Nurse holds the arm | Firm grip, warmth | Guide places the charging port on the forearm | Offer the arm | none | `port_place` | nurse tap (Next) |
| 2 | `swab` | Alcohol swab | Cold, wet, brief | Port is cooled and polished; frost shimmer | Watch the port glow | none | `frost` | nurse tap (Next) |
| 3 | `countdown` | Pause before needle | Nurse says: three, two, one | Three pulses of light at the port, 800 ms apart | Take a breath | none | `pulse` | nurse tap (**CONNECT**) |
| 4 | `connect` | Needle contact | Sharp onset | Cable clicks into the port | Look at the port | one pulse | `click` | auto, 400 ms |
| 5 | `charge` | Injection | Pressure, spreading ache, 3 to 5 s | Energy bar fills; lantern brightens; flow only while arm is still and head is on port | Stay still so the flow continues | ramp 0.2 → 1.0 | `flow_loop` | nurse tap (**NEEDLE OUT**) |
| 6 | `release` | Needle out | Release | Cable disconnects; lantern fully lit | Exhale | stop | `complete` | nurse tap (Next) |
| 7 | `seal` | Cotton and plaster | Pressure, adhesive | Seal placed over the port; charge mark remains on the arm | Look at the mark | none | `seal` | nurse tap (**DONE**) |

## Config

| Key | Value | Used by |
|---|---|---|
| `stillnessThresholdMps` | 0.05 | Vision, StillnessMonitor (M2) |
| `stillnessWindowMs` | 300 | Vision, StillnessMonitor (M2) |
| `headOnPortDegrees` | 25 | Vision, AttentionProxy (M2) |
| `chargeRatePerSecond` | 0.25 | SessionReducer: charge fills at this rate while armStill and headOnPort |
| `rampIntensity` | [0.2, 1.0] | Haptic role: start and end intensity of the continuous event |
| `rampSharpness` | 0.3 | Haptic role: sharpness of the continuous event |
| `rampDurationMs` | 4000 | Haptic role: time to go from start to end intensity (added in M1; the ramp then holds until NEEDLE OUT) |

## Who owns what

- **Headset (`vision` role)** hosts the session. It runs the reducer and a 10 Hz tick, broadcasts `stepChanged` on every phase change, `presence` on every tick, and hands a newly joined companion the current step.
- **Nurse** sends `stepChanged(next step)` as a request, or `connect` on the countdown step, or `reset`. The host only honours a request for the step immediately after the current one, so a double tap cannot skip.
- **Haptic** reacts only to each step's `haptic` field: `pulse`, `ramp`, `none` (stop).
- **Parent** mirrors the step list. The prompt line is Milestone 3.

Reserved step ids in `stepChanged` that are not rows: `idle`, `complete`.

## Wire format

Every message is one JSON envelope sent reliably over MultipeerConnectivity (service `_chargeup._tcp`):

```json
{"seq": 12, "message": {"type": "stepChanged", "stepId": "charge", "hostTimestamp": 1791815136.08}}
```

Types: `hello{role}`, `stepChanged{stepId, hostTimestamp}`, `connect{nurseTimestamp}`, `presence{headOnPort, armStill, charge}`, `reset{}`. `seq` is monotonic per sender; receivers drop anything not greater than the last accepted `seq` from that sender. A `hello` always resets the gate for its sender.
