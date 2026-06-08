import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/ai_service.dart';
import '../utils/matte_ops.dart';

/// Phase 7 — editable cutout matte state. Holds the detected base matte plus
/// the user's refine dabs and edge parameters, and exposes a derived "final"
/// matte (base → dabs → edge shift → feather) used for preview and export.
///
/// Dabs are stored and re-applied to the base each recompute so refine is
/// non-destructive and the edge sliders stay live.
class MatteEditState {
  /// The base matte from detection (null until detected).
  final CutoutResult? base;

  /// Refine dabs applied on top of the base, in order.
  final List<MatteDab> dabs;

  /// Edge feather radius in px (0 = none) and edge shift (-1..1).
  final int featherRadius;
  final double edgeShift;

  /// Brush settings for the refine tool.
  final double brushRadius; // normalized 0..1 of longest side
  final bool brushAdd; // true = add subject, false = erase

  const MatteEditState({
    this.base,
    this.dabs = const [],
    this.featherRadius = 2,
    this.edgeShift = 0.0,
    this.brushRadius = 0.05,
    this.brushAdd = true,
  });

  bool get hasMatte => base != null;

  MatteEditState copyWith({
    CutoutResult? base,
    List<MatteDab>? dabs,
    int? featherRadius,
    double? edgeShift,
    double? brushRadius,
    bool? brushAdd,
    bool clear = false,
  }) {
    if (clear) return const MatteEditState();
    return MatteEditState(
      base: base ?? this.base,
      dabs: dabs ?? this.dabs,
      featherRadius: featherRadius ?? this.featherRadius,
      edgeShift: edgeShift ?? this.edgeShift,
      brushRadius: brushRadius ?? this.brushRadius,
      brushAdd: brushAdd ?? this.brushAdd,
    );
  }

  /// Compute the final matte from base + dabs + edge shift + feather.
  /// Returns null if there's no base matte.
  CutoutResult? buildFinal() {
    final b = base;
    if (b == null) return null;
    var alpha = Uint8List.fromList(b.alpha);
    for (final d in dabs) {
      alpha = MatteOps.paintDab(alpha, b.width, b.height, d);
    }
    if (edgeShift != 0) {
      alpha = MatteOps.shiftEdge(alpha, b.width, b.height, edgeShift);
    }
    if (featherRadius > 0) {
      alpha = MatteOps.feather(alpha, b.width, b.height, radius: featherRadius);
    }
    return CutoutResult(alpha: alpha, width: b.width, height: b.height);
  }
}

class MatteEditNotifier extends StateNotifier<MatteEditState> {
  MatteEditNotifier() : super(const MatteEditState());

  void setBase(CutoutResult matte) =>
      state = MatteEditState(base: matte); // fresh dabs/params on new detection

  void addDab(MatteDab dab) =>
      state = state.copyWith(dabs: [...state.dabs, dab]);

  void undoDab() {
    if (state.dabs.isEmpty) return;
    state = state.copyWith(dabs: state.dabs.sublist(0, state.dabs.length - 1));
  }

  void clearDabs() => state = state.copyWith(dabs: const []);

  void setFeather(int r) => state = state.copyWith(featherRadius: r);
  void setEdgeShift(double v) => state = state.copyWith(edgeShift: v);
  void setBrushRadius(double r) => state = state.copyWith(brushRadius: r);
  void setBrushAdd(bool add) => state = state.copyWith(brushAdd: add);

  void reset() => state = const MatteEditState();
}

final matteEditProvider =
    StateNotifierProvider<MatteEditNotifier, MatteEditState>(
        (ref) => MatteEditNotifier());
