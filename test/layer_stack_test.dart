import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pixelvault/models/layer.dart';
import 'package:pixelvault/providers/layer_provider.dart';

void main() {
  late ProviderContainer c;
  LayerNotifier n() => c.read(layerProvider.notifier);
  LayerStack s() => c.read(layerProvider);

  setUp(() {
    c = ProviderContainer();
    n().initBase();
  });
  tearDown(() => c.dispose());

  test('initBase creates a single selected base layer', () {
    expect(s().layers.length, 1);
    expect(s().layers.first.kind, LayerKind.base);
    expect(s().selectedId, s().layers.first.id);
  });

  test('add places layer on top and selects it', () {
    final id = n().add(LayerKind.text, name: 'Hello');
    expect(s().layers.length, 2);
    expect(s().layers.last.id, id); // top = last
    expect(s().selectedId, id);
  });

  test('visibility toggles', () {
    final id = n().add(LayerKind.sticker, name: '⭐');
    expect(s().selected!.visible, isTrue);
    n().toggleVisible(id);
    expect(s().selected!.visible, isFalse);
  });

  test('opacity clamps to 0..1', () {
    final id = n().add(LayerKind.image, name: 'Cutout');
    n().setOpacity(id, 1.5);
    expect(s().selected!.opacity, 1.0);
    n().setOpacity(id, -0.2);
    expect(s().selected!.opacity, 0.0);
  });

  test('blend mode sets and maps to a Flutter BlendMode', () {
    final id = n().add(LayerKind.image, name: 'Overlay');
    n().setBlend(id, LayerBlend.screen);
    expect(s().selected!.blend, LayerBlend.screen);
    expect(LayerBlend.multiply.toBlendMode().toString(), contains('multiply'));
  });

  test('duplicate inserts a copy directly above the original', () {
    final id = n().add(LayerKind.text, name: 'A');
    n().setOpacity(id, 0.5);
    final beforeLen = s().layers.length;
    n().duplicate(id);
    expect(s().layers.length, beforeLen + 1);
    final i = s().indexOf(id);
    final dup = s().layers[i + 1];
    expect(dup.id, isNot(id)); // fresh id
    expect(dup.name, 'A copy');
    expect(dup.opacity, 0.5); // properties carried over
    expect(s().selectedId, dup.id);
  });

  test('reorder moves a layer within the stack', () {
    final a = n().add(LayerKind.text, name: 'A'); // index 1
    final b = n().add(LayerKind.text, name: 'B'); // index 2 (top)
    // Stack: [base, A, B]. Move B (index 2) to bottom-most non-base (index 1).
    n().reorder(2, 1);
    final ids = s().layers.map((l) => l.id).toList();
    expect(ids[1], b);
    expect(ids[2], a);
  });

  test('remove drops the layer and reselects', () {
    final id = n().add(LayerKind.sticker, name: 'X');
    n().remove(id);
    expect(s().indexOf(id), -1);
    expect(s().layers.length, 1); // base remains
    expect(s().selectedId, s().layers.last.id);
  });
}
