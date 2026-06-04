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
- [x] Edit history (undo/redo per step)
- [x] Batch edit screen — select multiple photos, apply filter
- [x] Collage screen — layout picker UI
- [x] Settings — dark mode, JPEG quality, export format
- [x] SQLite database for edit history and presets
- [x] No internet permission in AndroidManifest
- [x] Light + dark theme

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
- [x] 10-tool editor tab bar (Filter → Sticker)
- [x] Before/after compare (hold photo)
- [x] Edit history with undo/redo throughout all tools
