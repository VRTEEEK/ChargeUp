# Asset drop-in contract

Designed models and textures go into the Reality Composer Pro package at `Apps/ChargeUpVision/Assets/ChargeUpAssets` (open `Package.realitycomposerpro`). Models (USDZ) go inside `Sources/ChargeUpAssets/ChargeUpAssets.rkassets/`, where Reality Composer Pro's tooling compiles them into the app. PNGs the app must read back as images (`sleeve_tile`, `port_marker`) go in `Sources/ChargeUpAssets/Textures/` as plain resources, because a PNG inside `.rkassets` becomes a GPU texture and cannot be handed to image tracking. The app loads each asset **by file name** when the operator taps Start, just before the immersive space opens. A missing file is not an error: the app uses its procedural placeholder for that slot and the operator window's Assets line says which slots are placeholders. No code changes are needed to swap an asset; the file name is the contract.

Units: metres, Y up, origin as described per slot. Export USDZ from Reality Composer Pro or Blender with "meters per unit = 1". Keep triangle counts modest (under about 20k per lantern); the scene runs at 90 Hz with up to a dozen lanterns in the sky.

## Slots

| File name | Format | Scale and origin | Material names the app looks for | Placeholder today |
|---|---|---|---|---|
| `lantern_hero.usdz` | USDZ | Any height in metres, +Y up (the delivered hero is 0.25 m tall, 0.12 m wide, 18k triangles). Origin anywhere on the vertical axis: the app centres the model's visual bounds on the lantern position, so base-origin and centre-origin files both sit where the placeholder sat. The cable socket is derived from the bounds (36 % of the height up, at the front) | `Glass` (receives the LanternGlass shader; its `fill` drives the rising light; its own base-colour texture is not used), `Brass` or anything else untouched | Glass cylinder with frame, core and fill column |
| `lantern_round.usdz`, `lantern_tall.usdz`, `lantern_square.usdz` | USDZ | Same as hero. Absent for now: a missing variant falls back to the hero model, so the sky uses the hero at variant scale until distinct variants arrive. The sky picks a variant from a session record's `variant` field; records that say `lantern` cycle through the three | `Glass` as above | Same as hero, scaled by `config.sky.smallScale` |
| `port_ring.usdz` | USDZ | About 0.045 m across, origin at the base on the skin plane, +Y out of the skin (dome up); +X toward the hand (arm) or along the marker width (chest). The delivered ring is 0.045 × 0.010 m, 5,255 triangles | `Glass` receives the LanternGlass shader; the step visuals drive its `glowColor` and `glowIntensity` (cream glow, frost tint, countdown pulses, charge). Any `Glow` PBR material is driven too. `Brass` untouched | Flat blue emissive disc |
| `port_plate.usdz` | USDZ | Chest only. Origin at the plate centre on the skin plane, +Y out of the skin, dome up. The delivered plate is 0.080 × 0.057 m, 0.0097 m thick, 6,000 triangles, with the dome offset from the plate centre. At load the app measures the Glass mesh's XZ centre, logs it, and shifts the plate by the negative so the dome sits at the port pose; `config.chestPort.portOffsetFromMarkerMm` must therefore point at the dome, not the plate centre | `Glass` receives the LanternGlass shader (fill held at 1 via `assetOverrides.port_plate.glassMask: false`); `Brass` untouched | Soft-edged rounded box |
| `plug.usdz` | USDZ | The cable end that sits in the port. Origin where it meets the port; +Y points away from the skin along the cable | none | A short bright cylinder at the port end of the cable |
| `spark.usdz` or `Textures/spark.png` | USDZ, or PNG with alpha, centred | The single flush spark and the charge packets. A model is used if present, else the PNG as a sprite on a plane that always faces the viewer (about 0.018 m across, 0.029 m for the flush spark), else the procedural sphere | model: any emissive material, untouched | Emissive sphere |
| `charge_mark.usdz` or `Textures/charge_mark.png` | USDZ, or PNG with alpha | The mark left on the sleeve or dressing at release. A model is used if present, else the PNG as a flat sprite 0.052 m across on the skin plane; the fade is animated on the entity's opacity | none | Gold emissive disc |
| `Textures/sleeve_tile.png`, `Textures/sleeve_tile_soft.png` | PNG, square, seamless, opaque | The tiled surface over the access site: on the arm a tube around the forearm (length `config.sleeve.lengthMm`, radius from `config.forearm.forearmRadiusMm`, surface at the skin); on the chest a flat surround under the plate (`config.sleeve.surroundSizeMm`). `config.sleeve.tile` picks which file (default `sleeve_tile_soft`; if that file is absent the plain tile is used and the operator window says so), `config.sleeve.opacity` (0.6) and `config.sleeve.tileRepeat` (3) set the look. This tube is placeholder geometry hung off the port pose so the texture can be seen; the real forearm sleeve with occlusion (Milestone 2 task 2) is not built | n/a | no surface |
| `Textures/port_marker.png` | PNG, square, opaque, high contrast, asymmetric (the delivered emblem is 1254 px) | Printed at exactly `config.chestPort.markerSizeMm` (50 mm). The app registers it as the image-tracking reference at that physical width, so a designed emblem drops in at the same 50 mm. `docs/port-marker.pdf` is regenerated from this file at 50 mm | n/a | none (the file ships) |

## Verified so far

Checked in the visionOS simulator with the delivered `lantern_hero`, `port_ring` and `port_plate`: each loaded under its slot, `Glass` was replaced by the LanternGlass shader, brass rendered with its textures, and with the height-based mask the hero's light rises from the base during the infusion (its UVs are an atlas, which is why the mask is positional). Removing a file puts the procedural placeholder back with no code change.

The ShaderGraph uses only nodes RealityKit accepts (`ND_position_vector3`, `ND_separate3_vector3`, `ND_subtract_float`, `ND_divide_float`, `ND_smoothstep_float`, `ND_multiply_color3FA`, `ND_realitykit_pbr_surfaceshader`). `ND_invert_float` is not available on visionOS 2.

`port_ring` and `port_plate` are alternatives, not layers: with `config.accessSite` arm the loader loads the ring and never requests the plate; with chestPort it loads the plate and never requests the ring. The unused one costs nothing.

Delivered 20 Oct 2026: `charge_mark.png`, `spark.png`, `port_marker.png` and `sleeve_tile.png`, all 1254 px square. The zip had no `sleeve_tile_soft.png`, so with the default config the app falls back to the plain tile and says so in the operator window; drop the soft file in and the default picks it up. The two RGBA sprites draw their glyph on a fraction of the canvas (spark 19 × 25 %, mark 41 × 89 %); the loader measures the opaque extent and scales the sprite plane so the glyph, not the canvas, fills the intended size. Opacity comes from a single-channel alpha mask the loader builds from the PNG, because RealityKit's opacity map reads a colour channel. The marker emblem has not been tracked on a device.

## Sleeve styles and the cable

`config.sleeve.style` is `glow` by default: `Materials/SiteGlow.usda`, a soft radial patch on the skin at the port (amber at the centre fading to nothing on UV distance, so the patch mesh never shows an edge) with `config.sleeve.tile` mixed in at `glow.tileOpacity` (0.25). On the arm its extent along the forearm grows from `glow.extentMinMm` (40) at cream to `glow.extentMaxMm` (140) at full charge, `glow.widthMm` across; on the chest it is a disc of `glow.chestDiscMm` around the dome. It brightens by `glow.pulseGain` with each countdown pulse. `style = tube` keeps the old textured tube or surround (placeholder geometry). `glow.intensity` is 0.9: the surface is unlit and not tone-mapped, so values much above 1 blow the centre to white.

The cable is `Materials/CableLight.usda` on a tube mesh rebuilt each frame along a parabolic sag (`visuals.cableSagM`, 0.03 at mid-span) from the port to the lantern socket: a core of `visuals.cableCoreMm` (6) in `visuals.cableColor` (`#FFB347`) and a halo of `visuals.cableHaloMm` (22) at `visuals.cableHaloOpacity` (0.22), both unlit until connect and then lit from the port end toward the lantern as the connect step's `lit` parameter grows. It is not present at all during countdown. The sparks run along the same curve. The tube is regenerated only when an endpoint has moved more than `config.cable.moveThresholdMm` (2) or the lit value changed, and never more than `config.cable.rebuildHz` (30) times a second; between rebuilds the sparks ride the last curve. The operator window shows the current rebuild rate.

## Companion (off by default)

`config.companion.enabled` (false) gates a character beside the lantern. Slots, all USDZ in the `.rkassets` folder; only the ones the sequence references are loaded:

| File name | Clip inside | Length | Used by |
|---|---|---|---|
| `companion_model.usdz` | Idle_3, breathing idle | 10 s | the rendered model; its own clip is the idle loop |
| `companion_clip_wave.usdz` | Wave_for_Help_2 | 1.5 s | cream (`waveIn`), at 0.8 |
| `companion_clip_listen.usdz` | Listening_Gesture | 9.3 s | countdown and connect (`listen`) |
| `companion_clip_look.usdz` | Short_Breathe_and_Look_Around | 7.8 s | flush (`lookOnce`); charge variety |
| `companion_clip_sway.usdz` | Happy_Sway_Standing | 10 s | charge variety, at 0.6 |
| `companion_clip_idle_alt.usdz` | Idle_02 | 1.9 s | charge variety |
| `companion_clip_fidget.usdz` | Idle_03 | 4.3 s | charge variety only if listed in `chargeVariety`; at most `fidgetMaxPerSession` (1) times |
| `companion_clip_heart.usdz` | Big_Heart_Gesture | 6 s | release (`heartCheer`), first |
| `companion_clip_cheer.usdz` | Cheer_with_Both_Hands | 3 s | release (`heartCheer`), second, at 0.8 |

Agree and Spin are no longer referenced and are not in the package. The clip files carry placeholder textures and are only read for their animation resource.

Rules: idle is a real loop of the model's own clip and is the one clip that loops. Every other clip plays once at `config.companion.speed` (0.7) or its entry in `speedOverrides`; every change, including into idle, cross-fades over `crossfadeS` (0.3) using the playback transition. Cues per step row (`companion` field): `waveIn` fades in over `fadeS`, waves once, idles; `idle`; `listen` runs the listen clip and keeps it running across following steps that also say listen; `lookOnce` looks around once, then idles; `charging` idles and every `chargeVarietyEverySMin` to `Max` (25 to 40) seconds plays one of `chargeVariety` (look, sway, idleAlt) chosen at random without repeating the last, then idles; `heartCheer` plays heart once as the lantern lights, then cheer once as it rises. Placement is unchanged: `heightM` tall, feet on the lantern's base plane, beside it on the side opposite `config.forearm.heldArm`, world-anchored with the lantern. No reaction to presence or charge pauses, no sound, nothing on the companions.

Clips from other files play on the model by retargeting (verified 27 Oct 2026: probe reported "retargeting works" on the first foreign clip); the entity-swap fallback remains and reports in the operator window if a clip ever moves nothing. Every clip starts and ends on the same pose, which is what makes the cross-fades clean.

## Per-slot overrides

`config.assetOverrides` in sequence.json, keyed by slot name:

| Key | Default | Meaning |
|---|---|---|
| `glassMask` | true | When false the Glass shader's `fill` is held at 1, so the glow is a constant emissive with no UV mask. Set for `port_ring` and `port_plate`: on a shallow dome the mask read as the whole dome switching on, so the ring glows evenly with its intensity following the step, and the plate's dome glows at the shader default. |

## The Glass material

`Materials/LanternGlass.usda` is a ShaderGraph material with these parameters:

| Parameter | Type | Meaning |
|---|---|---|
| `fill` | float 0…1 | Emissive is masked against object-space height: points whose normalised height (`(y - baseY) / height`) is below `fill` glow, so light rises from the base whatever the UV layout. The app sets `baseY` and `height` from the Glass mesh bounds at load. |
| `softness` | float | Width of the soft edge at the top of the light, as a fraction of the height (0.08). |
| `baseY`, `height` | float | The Glass mesh's lowest y and its height in the model's frame; set by the app, not by hand. |
| `glowColor`, `glowIntensity` | color, float | The light. |
| `glassColor`, `glassOpacity` | color, float | The glass when dark. |

At load, every material named `Glass` in a lantern USDZ is replaced by an instance of this material (the loader walks every model component and compares `Material.name`; entity names and subsets are ignored). The app then sets `fill` as the session charges (0 dark, 1 lit; the sky uses the fill the session reached) and `glowIntensity` from `config.lantern.glowDark`, `glowCharging` (+ `glowGlance` while the child looks at it), `glowLit`. Name the glass material exactly `Glass` in the DCC tool; the name survives USDZ export (verified with the delivered hero: materials `Brass` and `Glass`, Glass replaced on one component).

Known limit: the shader's glass is a flat `glassColor` at `glassOpacity` 0.3, so a textured glass (the hero's amber) loses its texture once replaced, and the glow is attenuated by the low opacity. Both are material defaults in `LanternGlass.usda`, not config; changing them is a shader edit.

## Where the names live in code

`Apps/ChargeUpVision/Scene/AssetSlots.swift` holds the slot list and the loader. `config.chestPort.markerImage` names the marker file without extension. Nothing else in the app refers to an asset by file name.
