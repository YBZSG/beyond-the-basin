# Room arrivals: implemented contract and limits

`campaign_arrivals.gd` is additive and campaign-only. It covers the actual 28 source identities: original 0–7, expanded 0–3, poolrooms 0–2, reference 0–4, quiet **8–10**, formal 0–4. It never infers quiet/formal identity from overlapping renderer variant values.

## Integration

Create one Node above streamed rooms. At campaign/chapter setup call `configure(chapter_id, epoch)`, then `restore_seen(state.visited.keys())` for loaded discoveries. Do not restore visited every frame after `state.visit`, which would suppress the current arrival. Same-chapter epoch changes cancel transient effects but preserve seen identities. New chapters clear local seen history. `clear()` on leaving campaign clears everything.

Before updating a room, runtime supplies `campaign_source_mode` and `campaign_source_index` metadata from its matching catalog `room_specs` entry. Extras without an explicit source spec do not emit a cue. Identity is `chapter_id:room_key`, matching persistent visited keys.

Call `update_room(room, identity, ready, allowed, delta)` every active frame. `ready` must include collision/water readiness. `allowed` must exclude menus, loading, transitions, absent/unfocused player and unwanted HUD presentation. `set_suspended(true)` immediately clears pending/active effects; false allows future unseen entries. Runtime retains authority over both readiness and focus.

A room must remain the same valid ready/allowed instance for 0.35 active seconds. Leaving, pausing or entering an unready room resets dwell. A long/invalid frame cannot accumulate unbounded time. Seen entries never replay on threshold oscillation. Unknown chapters, wrong chapter/source pairings, invalid source indices and malformed identities are rejected. Maximum seen state is 28.

## What is implemented

- 28 distinct source-grounded Chinese titles and concise architectural/ambient descriptions; correct archived Quiet Wing index offset.
- Small non-intercepting top-right title/text card, source-specific muted accent, 0.55 s fade-in / 0.9 s fade-out, 3.8 s maximum active display. No floating world label, waypoint or puzzle solution.
- Optional original synthesized 1.2 s spatial audio signature: gentle water, drip, hum or air family with room-specific pitch. `set_audio_enabled(true)` requires coordinator authorization; the standalone module defaults silent. Campaign runtime ties this to its existing sound **and** ambience toggles, so normal enabled audio permits quiet arrival signatures and either existing mute suppresses them. It respects existing Ambience bus if present without modifying it; no third-party assets, looping or accumulating voices. Text equivalent remains available without sound.
- Real station-mounted courtesy fixture activation: three independently lit warm lenses in a permanent dark housing and a separate inspection tag/vane. Six patterns are selected by source mode: circuit cascade, bottom-up pressure rise, branched water route, center-out reading pass, ventilation breath and gradual daylight opening. Source index changes cadence/direction without changing puzzle state. One additive warm local light (range 2.8 m, energy at most 0.58) lights the station and nearby surfaces. It never replaces or mutates original fixtures.
- Courtesy materials are duplicated privately for the effect; originals and the vane pose are restored on completion/cancel. Objective needles, mirrors, levers, status lamps and solutions are untouched. `reduced_effects=true` disables vane motion and uses a uniform slow light envelope.
- One UI layer, at most one audio voice and one local courtesy light. Immediate cleanup on suspension, room change/unload, epoch change, chapter change, leaving campaign and Node destruction. A minimal always-process cleanup also handles a freed/unloaded room or SceneTree pause when the coordinator stops ticking. This loop never advances arrival timing.
- No camera ownership, FOV changes, forced movement, geometry/collision/water changes, original light mutation, strobe, flash or global audio-bus changes.

## What remains a design proposal, not implemented here

The broader design matrix describes actual acoustic crossfades/reverb treatment, additional hinged environmental props and whole-room architectural light reveals. This module does **not** claim those exist. What exists is an animated physical station inspection fixture, localized illumination, room title and optional original audio, not a whole-room cinematic or a seamless new corridor. Its audio is a quiet signature, not physical room acoustics or recordings of fans/showers. Chapter cinematics and progressive corruption are owned by separate presentation modules. The only world-space light is the bounded station courtesy light described above; it does not globally relight the room, chase the camera or neutralize corruption. Original architecture-light ownership remains with the corruption module.

## Verification

`godot --headless --path . --script tests/campaign/test_arrivals.gd`

Dedicated CPU/headless tests cover all 28 descriptions and bounded audio samples; first-entry dwell; doorway oscillation; repeated visits; unknown/mixed identity; pause/loading/unready; long frames; same/new epoch behavior; saved seen restoration; audio opt-in/cleanup; freed room; hard state and live-node budgets. No shared import was run by the arrivals implementer. Additional tests cover all six continuous light envelopes over 381 samples each, bounded intensity, reduced motion, private-material ownership, exact neutral restoration, unchanged objective poses, late station availability and cleanup not clobbering a newer material owner.

`tests/campaign/export_arrival_gallery.gd` exports the actual native station meshes with arrival materials at 0.20/0.70/1.35/3.25 seconds; `tests/campaign/render_arrival_gallery.py` renders that export with Blender. This offline asset/contact-sheet preview is **not an in-game screenshot** and its lighting exposure is not renderer equivalence. Headless success and offline rendering are not complete visual/audio acceptance: final game screenshots and listening remain necessary to assess context, CJK legibility, mix and aesthetic fit.

Latest focused run: **4,788 checks, zero failures**, including all 28 actual catalog station builds. Log: `tests/campaign/arrivals-test-result.log`.

Inspected offline preview: `docs/campaign/arrival-fixture-preview.png`. Columns are the six physical temporal patterns; rows sample 0.20, 0.70, 1.35 and 3.25 seconds. The first preview exposed poor off/on contrast in pale diffusers; the final kit uses smoked neutral glass and a warm activated tint, verified in the re-render. The header, needles and semantic status lamps are deliberately unchanged between animation samples; only the courtesy fixture and hanging inspection vane animate. Late-ready fixtures begin at zero intensity and fade over remaining cue time, rather than jumping to the current bright phase.
