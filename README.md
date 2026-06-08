# PixelVault 📸
**Free · Offline · Private · No Watermark · No Account**

A fully offline photo editor for Android & iOS built with Flutter.
All editing happens on the device — photos never leave the phone.

---

## 🚀 Quick Setup (5 steps)

### 1. Make sure Flutter is installed
```bash
flutter --version
# Should show Flutter 3.x or above
```

### 2. Clone / open the project
```bash
cd pixelvault
```

### 3. Install dependencies
```bash
flutter pub get
```

### 4. Connect your Android phone (USB debugging ON)
```bash
flutter devices
# You should see your phone listed
```

### 5. Run the app
```bash
flutter run
```

---

## 📁 Project Structure

```
lib/
├── main.dart                  ← App entry point + theme switching
├── theme/
│   └── app_theme.dart         ← Light & dark theme definitions
├── models/
│   ├── photo_model.dart       ← Photo data model
│   ├── edit_settings.dart     ← All adjustment values
│   └── filter_model.dart      ← 20 built-in filters
├── providers/
│   ├── gallery_provider.dart  ← Photo loading + batch selection
│   └── editor_provider.dart   ← Edit state + undo/redo history
├── screens/
│   ├── home_screen.dart       ← Gallery with tabs + grid
│   ├── editor_screen.dart     ← Full editor with tools + sliders
│   ├── batch_screen.dart      ← Batch edit multiple photos
│   ├── collage_screen.dart    ← Collage layout picker
│   └── settings_screen.dart   ← Theme, export, privacy info
├── widgets/
│   ├── adjustment_slider.dart ← Reusable slider for adjustments
│   └── filter_strip.dart      ← Horizontal filter strip
└── utils/
    ├── database_helper.dart   ← SQLite for history + presets
    └── image_processor.dart   ← Applies edits to images
```

---

## ✅ Phase 1 Features (Built)

- [x] Gallery screen — photo grid, tabs, batch select
- [x] Editor screen — filters, adjust sliders, undo/redo
- [x] 20 built-in offline filters
- [x] Brightness, contrast, saturation, highlights, shadows, warmth, vignette
- [x] Before/after compare (hold to reveal original)
- [x] Edit history (undo/redo per step) — persisted to SQLite; reopening a photo restores its last edit
- [x] Batch edit screen — select multiple photos, apply a filter, and save all to the gallery (real processing with progress + failure count)
- [x] Collage screen — layout picker + real export (cells composited "cover"-fit with borders, saved to gallery)
- [x] Settings — dark mode, JPEG quality, export format (all honored by the save pipeline)
- [x] SQLite database for edit history and presets
- [x] No internet permission in AndroidManifest
- [x] Light + dark theme

All save paths (single edit, batch, collage) share one `PhotoSaver` pipeline
that honors the export format/quality from Settings and writes to a `PixelVault`
gallery album. Editing is non-destructive — originals are never modified.

---

## ✅ Phase 2 (Complete)

- [x] HSL color tuning per channel — per-band hue/sat/lum grading with smooth membership weighting
- [x] Perspective fix tool — keystone correction via inverse bilinear warp
- [x] Healing / spot removal brush — patch-clone fill: each marked dab is repaired by blending a clean nearby patch with a feathered edge
- [x] Background blur (bokeh) — paint the subject to keep it sharp; everything outside the feathered focus mask is blurred (falls back to center-weighted radial blur if no subject is painted)
- [x] Selective edit brush — brush a region, then apply brightness/contrast/saturation/warmth only inside the feathered mask
- [x] Actual image saving to gallery — real pixel pipeline + `gal` write to a `PixelVault` album

All brush tools share a resolution-independent `BrushMask` model (normalized
dabs), so masks rasterize correctly at full output resolution. A single brush
stroke is one undo step (live updates during the drag, committed on release).

> **Note on bokeh:** the focus mask is user-painted rather than ML-segmented.
> This is intentional — it avoids a heavy on-device model, works on any subject
> (not just people), and gives the user direct control. Automatic
> portrait-segmentation (e.g. a TFLite mask) remains a possible future addition.

---

## 📦 Dependencies

| Package | Purpose |
|---|---|
| flutter_riverpod | State management |
| photo_manager | Read photos from device gallery |
| image | Image processing (crop, adjust, filters) |
| sqflite | Local SQLite database |
| path_provider | Device file paths |
| google_fonts | Inter font |
| permission_handler | Request photo permissions |
| flutter_colorpicker | Colour selection UI |

---

## 🔒 Privacy Guarantee

This app has **no internet permission** in `AndroidManifest.xml`.
It is physically incapable of sending any data over the network.

```xml
<!-- NO internet permission — by design -->
<!-- android.permission.INTERNET is intentionally absent -->
```

---

## 🎨 App Name
**PixelVault** — Your photos. Your device. Your vault.

---

## ✅ Phase 3 — Unique Features (Built)

- [x] Text overlay — add/move/resize/delete text layers on photo
- [x] Drawing canvas — freehand brush with 9 preset colors + custom picker
- [x] Eraser tool — erase specific parts of drawing
- [x] Sticker overlay — 40 emoji stickers, drag + resize + delete
- [x] Collage maker — 6 layouts (2-photo, 4-grid, magazine, 6-grid + more)
- [x] Collage border — adjustable width + 5 color options
- [x] Custom preset saving — save any edit as a named reusable preset
- [x] Presets screen — apply, delete, view summary of saved presets
- [x] 11-tool editor tab bar (Filter → Sticker, incl. Curves)
- [x] Before/after compare (hold photo)
- [x] Edit history with undo/redo throughout all tools

---

## ✅ Phase 4 — Pro tools & performance

- [x] **Tone Curves** — draggable 5-point RGB master curve (LUT-based), with live preview
- [x] **Non-blocking save** — full-resolution decode/process/encode runs on a background isolate, so saving never freezes the UI
- [x] **Full-resolution overlay export** — text/drawing/stickers are composited onto the photo at its native resolution via a dart:ui canvas (previously capped at screen resolution)
- [x] **Non-destructive re-edit** — reopening a photo restores its last saved edit (all settings, incl. curve) so you can keep tweaking
- [x] **Interactive crop** — draggable crop box mapped to the real photo rect (handles letterboxing correctly)
- [x] **Wider input formats** — JPEG, PNG, WebP, TIFF, PSD, BMP, GIF decode natively (via the `image` package); HEIC / RAW originals fall back to a full-size OS-provided JPEG so they still open and save

---

## ✅ Phase 5 — Hybrid AI (offline-first)

PixelVault is **offline by default**. AI is added without giving that up:

- [x] **AiService abstraction** — single seam the UI talks to; every capability declares whether it needs the network, so on-device features always work and cloud features stay gated.
- [x] **AI Cutout (on-device)** — detects the subject and either saves it on a **transparent background (PNG)** or keeps it sharp while **blurring the background**. Runs entirely on a background isolate; **no network, no bundled model download** — works even with online AI turned off.
- [x] **One-time AI opt-in (persisted)** — Settings → *Enable online AI features*, **off by default**, with an explicit consent dialog. Only gates *future* cloud features (e.g. AI upscale / generative fill); on-device Cutout ignores it.
- [x] **Honest privacy UI** — when online AI is enabled, the Privacy section in Settings updates to say photos may be uploaded only when an online AI feature is used.

> **How Cutout works (model-free):** a classical segmentation pipeline —
> centre/colour-model subject prior → largest-connected-component → hole-fill →
> edge feather → bilinear upscale. The code has a clearly marked seam
> (`CutoutEngine._seamForTfliteModel`) where a TFLite model (U²-Net / MODNet)
> drops in later for sharper edges, with **no change** to the tool, save
> pipeline, or `CutoutResult` contract.

> **Privacy model note:** Android permissions are app-wide, so a build that can
> reach a server must declare `INTERNET`. The pure-offline build keeps the
> *OS-enforced* "no internet permission" guarantee. The hybrid build's promise
> is **"offline unless you opt in and tap an online AI feature, and we tell you
> first"** — weaker than the OS guarantee, but explicit and user-controlled.

---

## ⚠️ Known limitations (honest)

These are genuine gaps vs. apps like Snapseed / Lightroom:

- **No native HEIC / camera-RAW decoding** — handled via an OS JPEG fallback, not true RAW development. No exposure recovery from RAW data.
- **CPU pixel pipeline, not GPU** — adjustments run as Dart pixel loops (the live preview uses a downscaled copy for responsiveness; the GPU is only used for the canvas/overlay compositing). Very large images are slower than shader-based editors.
- **Healing is patch-clone**, not content-aware fill — visible on complex textures.
- **Background blur** comes in two forms: a manual/centre-weighted brush (Blur tool) and an automatic **AI Cutout** (subject detection). The Cutout uses a **classical, model-free** segmentation — good on clear subject/background separation, weaker on fine hair/edges than a trained TFLite matting model (the drop-in seam for which exists).
- **Selective edits are brush+feather masks** — no luminosity masks or gradient/radial filters.
- **No cloud AI yet** — the online-AI opt-in toggle and `AiService.needsNetwork` seam are in place, but no server-backed feature (upscale, generative fill) is wired. Adding one requires a backend + the `INTERNET` permission.
- True **GPU acceleration** and a **trained on-device ML matting model** would require heavy native/TFLite dependencies; deliberately deferred to keep the app lightweight (the classical cutout covers the common case offline today).
