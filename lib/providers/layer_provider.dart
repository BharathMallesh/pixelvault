import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/layer.dart';

/// Phase 6.1/6.2 — state + operations for the layer stack: add, remove,
/// reorder, select, and edit per-layer compositing (visibility, opacity, blend
/// mode). Kept independent of the editor's adjustment history for now; the two
/// merge during the 6.5 migration.
class LayerNotifier extends StateNotifier<LayerStack> {
  LayerNotifier() : super(const LayerStack());

  int _seq = 0;
  String _newId(LayerKind kind) =>
      '${kind.name}_${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

  /// Reset the stack to a single base photo layer. Called when a photo opens.
  void initBase({String name = 'Photo'}) {
    final base = Layer(id: _newId(LayerKind.base), kind: LayerKind.base, name: name);
    state = LayerStack(layers: [base], selectedId: base.id);
  }

  /// Add a layer on top of the stack and select it. Returns the new id.
  String add(LayerKind kind, {required String name, Object? content}) {
    final layer = Layer(id: _newId(kind), kind: kind, name: name, content: content);
    state = state.copyWith(
      layers: [...state.layers, layer],
      selectedId: layer.id,
    );
    return layer.id;
  }

  void select(String id) => state = state.copyWith(selectedId: id);

  void remove(String id) {
    final layers = state.layers.where((l) => l.id != id).toList();
    // Don't allow removing the last base layer into an empty stack selection.
    final sel = state.selectedId == id
        ? (layers.isNotEmpty ? layers.last.id : null)
        : state.selectedId;
    state = LayerStack(layers: layers, selectedId: sel);
  }

  /// Duplicate a layer, placing the copy directly above the original.
  void duplicate(String id) {
    final i = state.indexOf(id);
    if (i < 0) return;
    final src = state.layers[i];
    final copy = src.copyWith(name: '${src.name} copy');
    // copyWith keeps the same id; create a fresh one.
    final dup = Layer(
      id: _newId(src.kind),
      kind: src.kind,
      name: copy.name,
      visible: src.visible,
      opacity: src.opacity,
      blend: src.blend,
      mask: src.mask,
      maskWidth: src.maskWidth,
      maskHeight: src.maskHeight,
      maskInverted: src.maskInverted,
      content: src.content,
    );
    final layers = [...state.layers];
    layers.insert(i + 1, dup);
    state = state.copyWith(layers: layers, selectedId: dup.id);
  }

  /// Move a layer from [oldIndex] to [newIndex] (stack order; higher = on top).
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.layers.length) return;
    final layers = [...state.layers];
    final item = layers.removeAt(oldIndex);
    var target = newIndex;
    if (target > oldIndex) target -= 1; // account for the removal
    target = target.clamp(0, layers.length);
    layers.insert(target, item);
    state = state.copyWith(layers: layers);
  }

  void _update(String id, Layer Function(Layer) f) {
    final layers = [
      for (final l in state.layers) l.id == id ? f(l) : l,
    ];
    state = state.copyWith(layers: layers);
  }

  void toggleVisible(String id) =>
      _update(id, (l) => l.copyWith(visible: !l.visible));
  void setOpacity(String id, double v) =>
      _update(id, (l) => l.copyWith(opacity: v.clamp(0.0, 1.0)));
  void setBlend(String id, LayerBlend b) =>
      _update(id, (l) => l.copyWith(blend: b));
  void rename(String id, String name) => _update(id, (l) => l.copyWith(name: name));
  void setContent(String id, Object content) =>
      _update(id, (l) => l.copyWith(content: content));
}

final layerProvider =
    StateNotifierProvider<LayerNotifier, LayerStack>((ref) => LayerNotifier());
