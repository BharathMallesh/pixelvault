import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/layer.dart';
import '../widgets/text_tool.dart';
import '../widgets/sticker_tool.dart';
import '../widgets/draw_tool.dart';

/// Phase 6.5 (bridge approach) — presents the existing, working overlay systems
/// (text / drawing / stickers) as layers in the Layers panel WITHOUT rewriting
/// those tools or the save path.
///
/// Each overlay *group* is shown as one panel layer (Text, Drawing, Stickers),
/// plus the base Photo. The panel can show/hide a group; group visibility is
/// stored here and consumed by the editor when rendering/saving. Reorder and a
/// full per-element migration are the larger "full migration" step deferred in
/// the plan — this bridge ships the visible benefit (a real Layers panel that
/// reflects the actual composition) at low regression risk.

/// Visibility of each overlay group, keyed by a stable layer id.
class GroupVisibility {
  final bool text;
  final bool draw;
  final bool sticker;
  const GroupVisibility({this.text = true, this.draw = true, this.sticker = true});

  GroupVisibility copyWith({bool? text, bool? draw, bool? sticker}) =>
      GroupVisibility(
        text: text ?? this.text,
        draw: draw ?? this.draw,
        sticker: sticker ?? this.sticker,
      );
}

class GroupVisibilityNotifier extends StateNotifier<GroupVisibility> {
  GroupVisibilityNotifier() : super(const GroupVisibility());
  void toggleText() => state = state.copyWith(text: !state.text);
  void toggleDraw() => state = state.copyWith(draw: !state.draw);
  void toggleSticker() => state = state.copyWith(sticker: !state.sticker);
  void reset() => state = const GroupVisibility();
}

final groupVisibilityProvider =
    StateNotifierProvider<GroupVisibilityNotifier, GroupVisibility>(
        (ref) => GroupVisibilityNotifier());

// Stable ids for the bridged group layers.
const String kBaseLayerId = 'base_photo';
const String kTextGroupId = 'group_text';
const String kDrawGroupId = 'group_draw';
const String kStickerGroupId = 'group_sticker';

/// A read-only, derived list of layers describing the current composition for
/// the Layers panel. Recomputes when overlays or group visibility change.
final bridgedLayersProvider = Provider<List<Layer>>((ref) {
  final texts = ref.watch(textOverlaysProvider);
  final draws = ref.watch(drawStrokesProvider);
  final stickers = ref.watch(stickerOverlaysProvider);
  final vis = ref.watch(groupVisibilityProvider);

  // Bottom -> top: photo, drawing, stickers, text (text on top by convention).
  final layers = <Layer>[
    const Layer(id: kBaseLayerId, kind: LayerKind.base, name: 'Photo'),
  ];
  if (draws.isNotEmpty) {
    layers.add(Layer(
      id: kDrawGroupId,
      kind: LayerKind.draw,
      name: 'Drawing (${draws.length})',
      visible: vis.draw,
    ));
  }
  if (stickers.isNotEmpty) {
    layers.add(Layer(
      id: kStickerGroupId,
      kind: LayerKind.sticker,
      name: 'Stickers (${stickers.length})',
      visible: vis.sticker,
    ));
  }
  if (texts.isNotEmpty) {
    layers.add(Layer(
      id: kTextGroupId,
      kind: LayerKind.text,
      name: 'Text (${texts.length})',
      visible: vis.text,
    ));
  }
  return layers;
});
