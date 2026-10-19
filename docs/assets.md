# Asset drop-in contract

Designed models and textures go into the Reality Composer Pro package at `Apps/ChargeUpVision/Assets/ChargeUpAssets` (open `Package.realitycomposerpro`). Models (USDZ) go inside `Sources/ChargeUpAssets/ChargeUpAssets.rkassets/`, where Reality Composer Pro's tooling compiles them into the app. PNGs the app must read back as images (`sleeve_tile`, `port_marker`) go in `Sources/ChargeUpAssets/Textures/` as plain resources, because a PNG inside `.rkassets` becomes a GPU texture and cannot be handed to image tracking. The app loads each asset **by file name** when the operator taps Start, just before the immersive space opens. A missing file is not an error: the app uses its procedural placeholder for that slot and the operator window's Assets line says which slots are placeholders. No code changes are needed to swap an asset; the file name is the contract.

Units: metres, Y up, origin as described per slot. Export USDZ from Reality Composer Pro or Blender with "meters per unit = 1". Keep triangle counts modest (under about 20k per lantern); the scene runs at 90 Hz with up to a dozen lanterns in the sky.

## Slots

| File name | Format | Scale and origin | Material names the app looks for | Placeholder today |
|---|---|---|---|---|
| `lantern_hero.usdz` | USDZ | About 0.16 m tall, 0.10 m wide; origin at the centre of the body; +Y up; the cable socket is at (0, +0.09, +0.05) local (front, just under the cap) | `Glass` (receives the LanternGlass shader; its `fill` drives the rising light), anything else untouched | Glass cylinder with frame, core and fill column |
| `lantern_round.usdz`, `lantern_tall.usdz`, `lantern_square.usdz` | USDZ | Same as hero. The sky picks a variant from a session record's `variant` field; records that say `lantern` cycle through the three | `Glass` as above | Same as hero, scaled by `config.sky.smallScale` |
| `port_ring.usdz` | USDZ | Fits inside a 0.04 m disc; origin at the ring centre on the skin plane; +Y out of the skin; +X toward the hand (arm) or along the marker width (chest) | Any material named `Glow` gets its emissive driven by the step (cream glow, countdown pulses); others untouched | Flat blue emissive disc |
| `port_plate.usdz` | USDZ | Chest only. About 0.12 × 0.09 m, 3 mm thick; origin at its centre on the skin plane; +Y out of the skin | none | Soft-edged rounded box |
| `plug.usdz` | USDZ | The cable end that sits in the port. Origin where it meets the port; +Y points away from the skin along the cable | none | A short bright cylinder at the port end of the cable |
| `spark.usdz` | USDZ | The single flush spark and the charge packets. About 0.012 m across; origin at its centre | any emissive material; the app does not change it | Emissive sphere |
| `charge_mark.usdz` | USDZ | The mark left on the dressing. Fits a 0.05 m disc; origin at its centre on the skin plane; +Y out | none; opacity is animated on the entity | Gold emissive disc |
| `Textures/sleeve_tile.png` | PNG, square, power of two (1024 px) | Tiles around the forearm sleeve (Milestone 2 task 2, not built yet). Seamless in both axes | n/a | not used yet |
| `Textures/port_marker.png` | PNG, square, 300 dpi (591 px for 50 mm), high contrast, asymmetric | Printed at exactly `config.chestPort.markerSizeMm` (50 mm). The app registers it as the image-tracking reference at that physical size, so a designed emblem drops in at the same 50 mm | n/a | Block-pattern marker; `docs/port-marker.pdf` is its printable form |

## Verified so far

Checked in the visionOS simulator with a hand-written ASCII USD lantern carrying a material named `Glass`: the model loaded under `lantern_hero`, the material was replaced by the LanternGlass shader, the light rose from the base as `fill` increased during the infusion, the sky reused the same model, and the operator window reported it. Removing the file put the procedural placeholder back with no code change. A real USDZ export has not been through this yet; the first one should be checked for UV v direction (base = 0) and the exact material name.

The ShaderGraph uses only nodes RealityKit accepts (`ND_texcoord_vector2`, `ND_separate2_vector2`, `ND_subtract_float`, `ND_smoothstep_float`, `ND_multiply_color3FA`, `ND_realitykit_pbr_surfaceshader`). `ND_invert_float` is not available on visionOS 2 and was replaced by a subtract.

## The Glass material

`Materials/LanternGlass.usda` is a ShaderGraph material with these parameters:

| Parameter | Type | Meaning |
|---|---|---|
| `fill` | float 0…1 | Emissive is masked against the mesh's UV **v**: faces with v below `fill` glow, so light rises from the base. The lantern's UVs must run v = 0 at the base to v = 1 at the top. |
| `softness` | float | Width of the soft edge at the top of the light, in UV units (0.08). |
| `glowColor`, `glowIntensity` | color, float | The light. |
| `glassColor`, `glassOpacity` | color, float | The glass when dark. |

At load, every material named `Glass` in a lantern USDZ is replaced by an instance of this material; the app then sets `fill` as the session charges (0 dark, 1 lit; the sky uses the fill the session reached). Name the glass material exactly `Glass` in the DCC tool; the name survives USDZ export.

## Where the names live in code

`Apps/ChargeUpVision/Scene/AssetSlots.swift` holds the slot list and the loader. `config.chestPort.markerImage` names the marker file without extension. Nothing else in the app refers to an asset by file name.
