# PixelVault — Roadmap to a PicsArt-class Editor

> **Positioning:** PixelVault is an **own-branded** editor (not a PicsArt clone — no
> PicsArt name, UI, or assets). It stays **offline-by-default**; cloud AI is an
> **opt-in** add-on already scaffolded (`AiService.needsNetwork`, persisted toggle).
> This document is the build plan to reach feature parity in the areas that matter.

## Legend
- **Offline** = runs on-device, no network, keeps the privacy promise.
- **On-device ML** = needs a bundled model (TFLite); offline but adds app size.
- **Cloud** = needs a backend + paid AI API + the `INTERNET` permission.
- Effort: **S** ≈ 1–2 days · **M** ≈ 3–5 days · **L** ≈ 1–2 weeks · **XL** ≈ 3+ weeks.

---

## Where we are today (done)
- Core editing: crop/rotate/flip, 20 filters, full adjust set, HSL, curves, healing
  (patch-clone), perspective, vignette, selective brush.
- Creative: text overlays, freehand draw + eraser, 40 emoji stickers, collage (6
  layouts), custom presets, before/after.
- Save pipeline: isolate processing, full-res overlay compositing, gallery album.
- **Phase 5 (just shipped):** on-device AI Cutout (model-free), `AiService` seam,
  online-AI opt-in toggle.

The four requested areas, in dependency order:
**Layers/masking → Creative assets → Portrait/beauty → Cloud generative.**

---

## PHASE 6 — Layer & Mask Engine  *(foundation — most other features depend on it)*
**Why first:** background replace, double exposure, blend modes, non-destructive
stacking, and proper sticker/text z-ordering all require a real layer model.
Today overlays live in separate global providers; this unifies them.

| # | Feature | Type | Effort |
|---|---|---|---|
| 6.1 | `Layer` model (image/text/sticker/draw/adjustment kinds), `LayerStack` provider | Offline | M |
| 6.2 | Layer panel UI: reorder (drag), show/hide, opacity slider, delete, duplicate | Offline | M |
| 6.3 | Blend modes (normal, multiply, screen, overlay, soft-light, add, …) in the compositor | Offline | M |
| 6.4 | Per-layer **mask** (paint to hide/reveal) + invert | Offline | M |
| 6.5 | Migrate existing text/draw/sticker overlays onto the layer stack | Offline | M |
| 6.6 | Full-res layer compositor (extend `OverlayCompositor` to a layer renderer) | Offline | M |

**Risk:** this is a refactor of how the editor composes output. Do it behind the
current pipeline, switch over once at parity. **Outcome:** double exposure, photo
blending, and clone-onto-layer become near-free afterward.

---

## PHASE 7 — Cutout Refine + Background Replace  *(builds on Phase 5 + 6)*
| # | Feature | Type | Effort |
|---|---|---|---|
| 7.1 | Manual mask refine brush (add/erase) on the cutout matte | Offline | M |
| 7.2 | Edge feather/shift + matte preview overlay | Offline | S |
| 7.3 | Replace background: solid / gradient / chosen photo (uses layers) | Offline | M |
| 7.4 | "Save cutout as sticker" → feeds the sticker library (Phase 8) | Offline | S |
| 7.5 | **Optional upgrade:** TFLite matting model (U²-Net/MODNet) at `_seamForTfliteModel` | On-device ML | L |

**Note:** 7.1–7.4 sharply improve the *existing* classical cutout without a model.
7.5 is the quality leap (hair edges) and is isolated to one seam.

---

## PHASE 8 — Creative Assets
| # | Feature | Type | Effort |
|---|---|---|---|
| 8.1 | Sticker library: bundled packs + search + recents + user stickers (from cutouts) | Offline | M |
| 8.2 | Shapes, frames, borders | Offline | S |
| 8.3 | Overlay packs: light leaks, bokeh, dust, gradients (screen/add blend) | Offline | S |
| 8.4 | Custom brushes (neon/glitter/texture) for the draw tool | Offline | M |
| 8.5 | Rich text: font packs, arc/curve text, outline, shadow, gradient fill, stroke | Offline | M |

**Dependency:** 8.1 user-stickers and 8.3 overlays are best after Phase 6 (layers)
and 8.1 pairs with 7.4. Asset packs are bundled (no download → privacy intact).

---

## PHASE 9 — Portrait / Beauty Retouch
**Needs face landmarks.** Two options: (a) a small on-device face-landmark TFLite
model (offline, ~few MB), or (b) manual brush-based versions (no model). Plan
assumes (a) for auto features and keeps (b) as the no-model fallback.

| # | Feature | Type | Effort |
|---|---|---|---|
| 9.1 | Face/landmark detector (on-device model) + fallback manual mode | On-device ML | L |
| 9.2 | Skin smooth (frequency-separation / edge-preserving blur within face mask) | Offline | M |
| 9.3 | Blemish remove (extends existing heal, face-aware) | Offline | S |
| 9.4 | Teeth whiten / eye brighten / eye-colour (landmark-targeted) | Offline | M |
| 9.5 | Reshape / liquify (mesh warp brush) | Offline | M |
| 9.6 | Makeup (lip/cheek/brow tint on landmarks) | Offline | M |

**Risk:** 9.5 liquify is fiddly; 9.1 model licensing must be permissive (e.g.
MediaPipe-style) and bundled, not downloaded.

---

## PHASE 10 — Cloud Generative AI  *(the "wow" — backend + cost + INTERNET)*
**Gated entirely behind the existing opt-in toggle.** This is where PixelVault
stops being free-to-run: every call costs GPU money.

### 10.0 Backend prerequisites (must come first)
| # | Item | Effort |
|---|---|---|
| 10.0a | Thin API service (your server): auth/quota, image upload, job queue | L |
| 10.0b | AI provider integration (hosted model API or self-hosted GPU) | M |
| 10.0c | Add `INTERNET` permission to the *hybrid* build flavor only; keep an offline flavor | S |
| 10.0d | Cost controls: per-user credits, rate limit, abuse/NSFW filtering | M |
| 10.0e | Client `CloudAiService` impl behind `AiService`, with consent + progress UI | M |

### 10.x Generative features (each ≈ S–M client side once backend exists)
| # | Feature | Notes |
|---|---|---|
| 10.1 | AI Enhance / Upscale | Lowest-risk first cloud feature; clear value |
| 10.2 | AI Background generator | Pairs with Phase 7 replace-background |
| 10.3 | Generative fill / object remove (inpaint) | Uses a painted mask |
| 10.4 | AI Expand (outpaint) | Extend canvas |
| 10.5 | Text→Image generator | Highest infra cost; do later |
| 10.6 | Style transfer / AI filters | Can be partly on-device later |

**Hard truths for Phase 10:**
- **Cost:** generative calls cost real money per image → you need monetization
  (credits/subscription) or you bleed cash. Plan a free on-device tier + paid AI tier.
- **Legal/safety:** generative content needs an NSFW/abuse filter and clear ToS.
- **Trademark:** never ship the name/branding/assets of PicsArt.
- **Privacy trade:** the hybrid flavor loses the OS-enforced no-internet guarantee
  (documented in README). Keep the pure-offline flavor as the privacy headline.

---

## Suggested sequencing & rationale
1. **Phase 6 (Layers)** — unlocks the most downstream features; do it first.
2. **Phase 7 (Cutout refine / bg replace)** — high visible value, mostly offline,
   leans on 5 + 6.
3. **Phase 8 (Assets)** — broad appeal, low risk, bundled = privacy-safe.
4. **Phase 9 (Beauty)** — high appeal; gated on a face-landmark model decision.
5. **Phase 10 (Cloud AI)** — last, because it needs a backend, a business model,
   and the biggest legal/cost commitments.

## Cross-cutting work (alongside any phase)
- Performance: keep heavy ops on isolates; consider GPU shaders for filters (XL,
  optional) if large-image speed becomes a complaint.
- Project save/restore: serialize the layer stack so edits are resumable (M) —
  natural to add during Phase 6.
- Monetization scaffolding: only needed when Phase 10 begins.

## What I'd build next if you say "go"
**Phase 6.1–6.2** (Layer model + layer panel). It's the keystone; almost everything
in your four requested areas gets simpler once it exists.
