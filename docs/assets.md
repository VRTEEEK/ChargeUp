# Asset drop-in contract

Designed models and textures go into the Reality Composer Pro package at `Apps/ChargeUpVision/Assets/ChargeUpAssets` (open `Package.realitycomposerpro`). Models (USDZ) go inside `Sources/ChargeUpAssets/ChargeUpAssets.rkassets/`, where Reality Composer Pro's tooling compiles them into the app. PNGs the app must read back as images (`sleeve_tile`, `port_marker`) go in `Sources/ChargeUpAssets/Textures/` as plain resources, because a PNG inside `.rkassets` becomes a GPU texture and cannot be handed to image tracking. The app loads each asset **by file name** when the operator taps Start, just before the immersive space opens. A missing file is not an error: the app uses its procedural placeholder for that slot and the operator window's Assets line says which slots are placeholders. No code changes are needed to swap an asset; the file name is the contract.

Units: metres, Y up, origin as described per slot. Export USDZ from Reality Composer Pro or Blender with "meters per unit = 1". Keep triangle counts modest (under about 20k per lantern); the scene runs at 90 Hz with up to a dozen lanterns in the sky.

## Slots

| File name | Format | Scale and origin | Material names the app looks for | Placeholder today |
|---|---|---|---|---|
| `lantern_hero.usdz` | USDZ | Any height in metres, +Y up (the delivered hero is 0.25 m tall, 0.12 m wide, 18k triangles). Origin anywhere on the vertical axis: the app centres the model's visual bounds on the lantern position, so base-origin and centre-origin files both sit where the placeholder sat. The cable socket is derived from the bounds (36 % of the height up, at the front) | `Glass` (receives the LanternGlass shader; its `fill` drives the rising light; its own base-colour texture is not used), `Brass` or anything else untouched | Glass cylinder with frame, core and fill column |
| `lantern_round.usdz`, `lantern_tall.usdz`, `lantern_square.usdz` | USDZ | Same as hero (currently copies of the hero file until distinct variants arrive). The sky picks a variant from a session record's `variant` field; records that say `lantern` cycle through the three | `Glass` as above | Same as hero, scaled by `config.sky.smallScale` |
| `port_ring.usdz` | USDZ | About 0.045 m across, origin at the base on the skin plane, +Y out of the skin (dome up); +X toward the hand (arm) or along the marker width (chest). The delivered ring is 0.045 × 0.010 m, 5,255 triangles | `Glass` receives the LanternGlass shader; the step visuals drive its `glowColor` and `glowIntensity` (cream glow, frost tint, countdown pulses, charge). Any `Glow` PBR material is driven too. `Brass` untouched | Flat blue emissive disc |
| `port_plate.usdz` | USDZ | Chest only. Origin at the plate centre on the skin plane, +Y out of the skin, dome up. The delivered plate is 0.080 × 0.057 m, 0.0097 m thick, 6,000 triangles, with the dome offset from the plate centre. At load the app measures the Glass mesh's XZ centre, logs it, and shifts the plate by the negative so the dome sits at the port pose; `config.chestPort.portOffsetFromMarkerMm` must therefore point at the dome, not the plate centre | `Glass` receives the LanternGlass shader (fill held at 1 via `assetOverrides.port_plate.glassMask: false`); `Brass` untouched | Soft-edged rounded box |
| `plug.usdz` | USDZ | The cable end that sits in the port. Origin where it meets the port; +Y points away from the skin along the cable | none | A short bright cylinder at the port end of the cable |
| `spark.usdz` | USDZ | The single flush spark and the charge packets. About 0.012 m across; origin at its centre | any emissive material; the app does not change it | Emissive sphere |
| `charge_mark.usdz` | USDZ | The mark left on the dressing. Fits a 0.05 m disc; origin at its centre on the skin plane; +Y out | none; opacity is animated on the entity | Gold emissive disc |
| `Textures/sleeve_tile.png` | PNG, square, power of two (1024 px) | Tiles around the forearm sleeve (Milestone 2 task 2, not built yet). Seamless in both axes | n/a | not used yet |
| `Textures/port_marker.png` | PNG, square, 300 dpi (591 px for 50 mm), high contrast, asymmetric | Printed at exactly `config.chestPort.markerSizeMm` (50 mm). The app registers it as the image-tracking reference at that physical size, so a designed emblem drops in at the same 50 mm | n/a | Block-pattern marker; `docs/port-marker.pdf` is its printable form |

## Verified so far

Checked in the visionOS simulator with a hand-written ASCII USD lantern carrying a material named `Glass`: the model loaded under `lantern_hero`, the material was replaced by the LanternGlass shader, the light rose from the base as `fill` increased during the infusion, the sky reused the same model, and the operator window reported it. Removing the file put the procedural placeholder back with no code change. A real USDZ export has not been through this yet; the first one should be checked for UV v direction (base = 0) and the exact material name.

The ShaderGraph uses only nodes RealityKit accepts (`ND_texcoord_vector2`, `ND_separate2_vector2`, `ND_subtract_float`, `ND_smoothstep_float`, `ND_multiply_color3FA`, `ND_realitykit_pbr_surfaceshader`). `ND_invert_float` is not available on visionOS 2 and was replaced by a subtract.

## Per-slot overrides

`config.assetOverrides` in sequence.json, keyed by slot name:

| Key | Default | Meaning |
|---|---|---|
| `glassMask` | true | When false the Glass shader's `fill` is held at 1, so the glow is a constant emissive with no UV mask. Set for `port_ring` and `port_plate`: on a shallow dome the mask read as the whole dome switching on, so the ring glows evenly with its intensity following the step, and the plate's dome glows at the shader default. |

## The Glass material

`Materials/LanternGlass.usda` is a ShaderGraph material with these parameters:

| Parameter | Type | Meaning |
|---|---|---|
| `fill` | float 0…1 | Emissive is masked against the mesh's UV **v**: faces with v below `fill` glow, so light rises from the base. The lantern's UVs must run v = 0 at the base to v = 1 at the top. |
| `softness` | float | Width of the soft edge at the top of the light, in UV units (0.08). |
| `glowColor`, `glowIntensity` | color, float | The light. |
| `glassColor`, `glassOpacity` | color, float | The glass when dark. |

At load, every material named `Glass` in a lantern USDZ is replaced by an instance of this material (the loader walks every model component and compares `Material.name`; entity names and subsets are ignored). The app then sets `fill` as the session charges (0 dark, 1 lit; the sky uses the fill the session reached) and `glowIntensity` from `config.lantern.glowDark`, `glowCharging` (+ `glowGlance` while the child looks at it), `glowLit`. Name the glass material exactly `Glass` in the DCC tool; the name survives USDZ export (verified with the delivered hero: materials `Brass` and `Glass`, Glass replaced on one component).

Known limit: the shader's glass is a flat `glassColor` at `glassOpacity` 0.3, so a textured glass (the hero's amber) loses its texture once replaced, and the glow is attenuated by the low opacity. Both are material defaults in `LanternGlass.usda`, not config; changing them is a shader edit.

## Where the names live in code

`Apps/ChargeUpVision/Scene/AssetSlots.swift` holds the slot list and the loader. `config.chestPort.markerImage` names the marker file without extension. Nothing else in the app refers to an asset by file name.
