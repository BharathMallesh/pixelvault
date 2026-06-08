import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Phase 6 — unified layer model. Everything composited onto the photo (the
/// base image, text, stickers, drawings, image overlays like cutouts, and
/// adjustment layers) is represented as a [Layer] in an ordered [LayerStack].
///
/// This is the foundation the plan calls for: layer reorder/opacity/visibility,
/// blend modes, and per-layer masks all hang off this model. Existing
/// text/draw/sticker overlay systems will be migrated onto it in step 6.5;
/// this commit introduces the model + stack without disrupting them.

enum LayerKind { base, image, text, sticker, draw, adjustment }

/// Porter-Duff-ish blend modes we support in the compositor (6.3). Mapped to
/// Flutter's [BlendMode] when rendering; kept as our own enum so the model
/// doesn't leak rendering types and can serialize cleanly.
enum LayerBlend {
  normal,
  multiply,
  screen,
  overlay,
  softLight,
  hardLight,
  darken,
  lighten,
  add,
  difference,
}

extension LayerBlendX on LayerBlend {
  BlendMode toBlendMode() {
    switch (this) {
      case LayerBlend.normal:
        return BlendMode.srcOver;
      case LayerBlend.multiply:
        return BlendMode.multiply;
      case LayerBlend.screen:
        return BlendMode.screen;
      case LayerBlend.overlay:
        return BlendMode.overlay;
      case LayerBlend.softLight:
        return BlendMode.softLight;
      case LayerBlend.hardLight:
        return BlendMode.hardLight;
      case LayerBlend.darken:
        return BlendMode.darken;
      case LayerBlend.lighten:
        return BlendMode.lighten;
      case LayerBlend.add:
        return BlendMode.plus;
      case LayerBlend.difference:
        return BlendMode.difference;
    }
  }

  String get label {
    switch (this) {
      case LayerBlend.normal:
        return 'Normal';
      case LayerBlend.multiply:
        return 'Multiply';
      case LayerBlend.screen:
        return 'Screen';
      case LayerBlend.overlay:
        return 'Overlay';
      case LayerBlend.softLight:
        return 'Soft Light';
      case LayerBlend.hardLight:
        return 'Hard Light';
      case LayerBlend.darken:
        return 'Darken';
      case LayerBlend.lighten:
        return 'Lighten';
      case LayerBlend.add:
        return 'Add';
      case LayerBlend.difference:
        return 'Difference';
    }
  }
}

/// A single layer. Common compositing properties live here; kind-specific
/// payloads (text string, sticker emoji, image bytes, draw strokes) live in the
/// typed [content]. The base photo is also a layer (kind == base) so the whole
/// composition is uniform.
@immutable
class Layer {
  final String id;
  final LayerKind kind;
  final String name;

  // Compositing.
  final bool visible;
  final double opacity; // 0..1
  final LayerBlend blend;

  // Optional per-layer mask: an 8-bit alpha plane (0 hides, 255 reveals) plus
  // its dimensions. Null = no mask (fully revealed). Added for 6.4.
  final Uint8List? mask;
  final int maskWidth;
  final int maskHeight;
  final bool maskInverted;

  // Kind-specific payload. The widget/compositor casts based on [kind].
  final Object? content;

  const Layer({
    required this.id,
    required this.kind,
    required this.name,
    this.visible = true,
    this.opacity = 1.0,
    this.blend = LayerBlend.normal,
    this.mask,
    this.maskWidth = 0,
    this.maskHeight = 0,
    this.maskInverted = false,
    this.content,
  });

  bool get hasMask => mask != null && maskWidth > 0 && maskHeight > 0;

  Layer copyWith({
    String? name,
    bool? visible,
    double? opacity,
    LayerBlend? blend,
    Object? content,
    bool clearMask = false,
    Uint8List? mask,
    int? maskWidth,
    int? maskHeight,
    bool? maskInverted,
  }) {
    return Layer(
      id: id,
      kind: kind,
      name: name ?? this.name,
      visible: visible ?? this.visible,
      opacity: opacity ?? this.opacity,
      blend: blend ?? this.blend,
      mask: clearMask ? null : (mask ?? this.mask),
      maskWidth: clearMask ? 0 : (maskWidth ?? this.maskWidth),
      maskHeight: clearMask ? 0 : (maskHeight ?? this.maskHeight),
      maskInverted: maskInverted ?? this.maskInverted,
      content: content ?? this.content,
    );
  }
}

/// Ordered stack of layers. Index 0 is the **bottom** (drawn first); the last
/// element is the **top** (drawn last). The base photo is normally at index 0.
@immutable
class LayerStack {
  final List<Layer> layers;
  final String? selectedId;

  const LayerStack({this.layers = const [], this.selectedId});

  Layer? get selected {
    for (final l in layers) {
      if (l.id == selectedId) return l;
    }
    return null;
  }

  int indexOf(String id) => layers.indexWhere((l) => l.id == id);

  LayerStack copyWith({List<Layer>? layers, String? selectedId, bool clearSelection = false}) {
    return LayerStack(
      layers: layers ?? this.layers,
      selectedId: clearSelection ? null : (selectedId ?? this.selectedId),
    );
  }
}
