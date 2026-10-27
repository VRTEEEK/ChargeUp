# Raw recordings, 20 Oct 2026

Two uncut simulator captures of one rehearsal-mode session, recorded at the same time with `xcrun simctl io <device> recordVideo --codec h264`. Nothing was trimmed, scaled or re-encoded.

| File | Device | Resolution | Length |
|---|---|---|---|
| `headset-rehearsal-child-view.mov` | Apple Vision Pro simulator, visionOS 2.3 (22N895) | 2732 × 2048, the simulator's full output | 86.3 s |
| `ipad-rehearsal-nurse-view-en.mov` | iPad Pro 13-inch (M5) simulator, iOS 27.0 (24A5408d) | 2064 × 2752 | 86.3 s |

## Exact configuration

- Code: commit `fe40b0f` (the committed `sequence.json`; nothing was changed for the recording).
- `config.accessSite` = `arm`; `config.forearm.simulatedForearm` = `true`, so the port rides the simulated path because the simulator has no hand tracking. The forearm sleeve (Milestone 2 task 2) does not exist yet.
- Designed assets loaded: `lantern_hero.usdz` (also serving the three sky variants by fallback), `port_ring.usdz`. Everything else placeholder. `port_plate` not loaded (arm). LanternGlass shader applied to both.
- Sky: `Documents/sessions.json` deleted before launch so it re-seeded to `config.sky.seededSessions` = 6; the session's lantern made it 7 (fill reached 0.034).
- Rehearsal: the iPad's Rehearsal toggle, `config.rehearsalIntervalMs` = 3000, driving the headset over Multipeer between the two simulators (the iPad linked to the visionOS app directly). Charge is time-based (`config.charge.demoDurationSec` = 90), so three seconds of infusion is a 3 % fill; that is what rehearsal mode produces.
- Headset launched with `CHARGEUP_AUTOSTART=1` (presses Start on launch; operator-only). No file control.
- Language on the iPad: English.

## Timeline inside the files

Both recordings start at 15:26:24 local and end at 15:27:51, two seconds after the session completed and before the rehearsal driver's automatic reset tap. Approximate offsets from the start of the file, from the headset's channel log:

| Offset | Event |
|---|---|
| 0 to 67 s | idle: six seeded lanterns, dark hero lantern, operator panel |
| ~67 s | START (cream) |
| ~70 s | clean |
| ~73 s | countdown |
| ~76 s | CONNECT → connect (auto 400 ms) → flush |
| ~79 s | charge |
| ~82 s | NEEDLE OUT → release: cable retracts, lantern rises over 3 s, mark fades onto the dressing |
| ~85 s | DONE → complete |

The long idle lead-in is in the raw file because the first attempts to flip the Rehearsal switch through the simulator's input tool did not register; the one that did is at ~64 s.

## Not in these files

Audio (the simulator renders the spatial sources but the capture has no audio track worth keeping), haptics, hand tracking, passthrough. The operator panel is visible in the headset capture because the simulator shows the operator window in the same frame as the immersive space; on the device the child does not see it.

---

# Companion recording, 27 Oct 2026

`headset-rehearsal-companion-child-view.mov`: Apple Vision Pro simulator (visionOS 2.3), 2732 × 2048 H.264, 95.7 s, uncut. The child's view through one rehearsal-mode session with the companion flag on, from before cream to complete.

## Exact configuration

- Code: the commit this file arrived in (PeerChannel teardown fix). `config.companion.enabled` was `true` for the run and is committed `false`.
- `config.rehearsalIntervalMs` was set to 12000 for the run so one session spans the recording (7 steps × 12 s); committed value is 3000. The iPad companion app was rebuilt with 12000 for this; the headset does not read that key.
- `config.accessSite` arm, simulated forearm, glow sleeve, real lantern and ring, amber cable, sky seeded to 6 at app launch and at 9 by this take (the driver had looped twice before the recorder started).
- Driven by the iPad simulator's Rehearsal toggle over Multipeer between the two simulators; headset launched with `CHARGEUP_AUTOSTART=1`, no file control.

## Timeline inside the file (from the headset's channel log)

| Offset | Event |
|---|---|
| 0 to 9 s | end of the previous session (complete), lantern lit in the sky |
| 9 s | reset to idle; companion fades out |
| 21 s | cream: glow appears on the port, companion fades in and waves |
| 33 s | clean: frost sparkles |
| 45 s | countdown: three pulses, companion listens |
| 57 s | CONNECT: cable appears and lights toward the lantern; flush follows at 58 s with the spark |
| 69 s | charge: packets on the cable, lantern filling, companion idling |
| 81 s | release: cable retracts, companion heart then cheer, lantern rises into the sky |
| 93 s | complete |

Not in the file: audio, haptics, hand tracking, passthrough. The operator panel is visible in the simulator frame; on the device the child does not see it.
