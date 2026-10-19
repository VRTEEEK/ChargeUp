# Charge Up — demo runbook (chemotherapy session)

For the person running the demo and for the judge who plays the nurse. Nothing here needs the code. Last updated 19 Oct 2026, before any device run: timings marked "expected" are from the simulator and will be corrected after the first headset session.

## Kit

- Apple Vision Pro (the child), charged, Charge Up installed, hand tracking allowed.
- iPad (the nurse), Charge Up companion installed.
- iPhone (the haptic phone), Charge Up companion installed, silent switch off, volume up.
- Optional second iPhone or iPad as the Parent screen.
- Personal Hotspot on the iPad. Name and password are on the inside of the kit lid, not in this file.
- A chair for the volunteer, a stool for the nurse at the volunteer's left side.
- If the chest-port build is ever used on a device: the printed marker (docs/port-marker.pdf at 100 %, 50 mm square) and tape. Not for this demo; the arm is the default.

## Power and pairing order

1. iPad on, Personal Hotspot on, Wi-Fi off on every other device.
2. Vision Pro on, joined to the hotspot. Open Charge Up. The operator window appears. Do not tap Start yet.
3. iPhone joined to the hotspot. Open Charge Up, pick **Haptic**. The screen goes black with a red dot.
4. (Optional) Parent device joined to the hotspot. Open Charge Up, pick the language on the role picker, pick **Parent**.
5. On the iPad, open Charge Up, pick the language, pick **Nurse**. The badge reads "Looking for headset".
6. Seat the volunteer, fit the headset, tap **Start** in the operator window. Within about 5 s every companion badge turns green and the operator window lists `nurse`, `haptic`, `parent`. The lantern appears in front of the volunteer with the sky of past lanterns above and behind it. The iPad button reads **START**.

Expected from Start to the first step: under 10 s.

## The 90-second script for the judge

Say the lines in bold to the volunteer. Tap the big button when the line is done. The button's label tells you what the tap means.

| Tap | Button says | Say | What the volunteer sees |
|---|---|---|---|
| 1 | START | "We're getting your lantern ready." | Sky of lanterns; the new lantern dark. |
| 2 | Next | "Cream on the port. It's making it sleepy." Hold the forearm. | A faint glow grows under the skin. |
| 3 | Next | "Just cleaning the skin, it's cold." | The port polishes, frost sparkles. |
| 4 | CONNECT | "Big breath, hold still: three, two, one." Tap on "one". | Three pulses of light, then the cable clicks in. The phone buzzes, rising for 4 s. |
| 5 | Next | "That's the flush. Watch the spark." | One spark climbs the cable; the lantern wakes. |
| 6 | NEEDLE OUT | "Your lantern is filling on its own. You can rest." Wait as long as you like; in the demo 90 s fills it. | Packets run up the cable; the fill rises; looking at the lantern brightens it. |
| 7 | DONE | "And out. Watch it rise." | The cable retracts, the lantern lights fully and rises into the sky; a mark fades onto the dressing. |
| 8 | RESET | (nothing) | Everything returns to idle; the sky has one more lantern. |

Stillness and attention are asked for at taps 4 only. During tap 6 the volunteer can move and look around.

Between judges: tap RESET, then START again. The sky keeps the previous judge's lantern.

## Rehearsing alone

On the iPad, the **Rehearsal** toggle taps the button every 3 s and loops. Use it to watch the headset scene with no second person.

## What to do when

| Symptom | Do this |
|---|---|
| A badge stays "Looking for headset" past 10 s | Check the device is on the hotspot, not Wi-Fi. Kill and reopen the companion. The headset keeps advertising; no need to touch it. |
| Badge says "Reconnecting to headset, step held" | The companion lost the link. Wait 5 s; it reconnects on its own and lands on the current step. The session does not reset. |
| Operator window shows "Reconnecting: nurse" | Same thing seen from the headset. The step is held. Carry on once it clears. |
| Button is greyed out | Either not linked (see above) or the sequence is on the 400 ms automatic step; wait a moment. |
| Port disc is dim or frozen | The headset lost the forearm (a hand over the wrist). It holds the last place for 2 s then dims to half; it recovers on its own. Do not move the arm to "help". |
| Port is on the wrong side of the arm | Operator: `config.forearm.dorsalAxis` in sequence.json, flip the sign. Rebuild. Not a demo-day fix. |
| No haptics | Check the iPhone is in the Haptic role with a green dot and the volume is up. The pulse and ramp are driven by step changes; tap RESET then START to retrigger. |
| Sky is empty | Operator window: Reset Sky re-seeds six lanterns. |
| Headset shows nothing after Start | Operator window Stop, then Start again. If the Forearm line says `unauthorized`, open Settings on the headset and allow hand tracking for Charge Up. |
| Everything is wrong | Operator window Stop; force-quit all three apps; follow the power and pairing order again. Under 2 minutes. |

## After each session

- The headset writes `chargeup-session-<date>.csv` (step, hostTimestamp, armStill, headOnPort, charge at 10 Hz) and updates `sessions.json` in its Documents folder. Both are visible in Files on the headset.
- The iPad's **Export log** shares the message log with connect round-trip times.

## Operator-only switches

Nothing in the child's view can be triggered by the child. The operator window (headset) has Reset session, Reset Sky and Stop. Debug flags (`CHARGEUP_AUTOSTART`, `CHARGEUP_DEBUG_FILE_CONTROL`) exist only for the simulator and are off unless set in the environment at launch.
