import 'dart:typed_data';

/// Phase 10 (scaffold) — interface for server-backed generative AI.
///
/// IMPORTANT — current status: this is a deliberate scaffold, NOT a working
/// cloud feature. There is no backend, and the app intentionally has no
/// `INTERNET` permission, so the default [DisabledCloudAiService] never makes a
/// network call. It exists so the UI, the opt-in gating, and the call sites are
/// all in place; a real implementation drops in later without touching callers.
///
/// To make this live you would:
///   1. Stand up a backend (auth/quota, upload, AI provider, NSFW filter).
///   2. Add the `INTERNET` permission to a *hybrid* build flavor (keeping the
///      offline flavor as the privacy headline).
///   3. Implement [CloudAiService] with an HTTP client pointing at your API.
///   4. Register that implementation in [cloudAiServiceProvider] (or DI).
///
/// All cloud capabilities are gated behind the user's online-AI opt-in
/// (see settings_screen `aiOnlineEnabled`) — the UI must not call these unless
/// the user has explicitly opted in.

enum CloudAiFeature {
  enhanceUpscale,
  generativeFill,
  expandOutpaint,
  backgroundGenerate,
  textToImage,
}

extension CloudAiFeatureX on CloudAiFeature {
  String get label {
    switch (this) {
      case CloudAiFeature.enhanceUpscale:
        return 'AI Enhance / Upscale';
      case CloudAiFeature.generativeFill:
        return 'Generative Fill';
      case CloudAiFeature.expandOutpaint:
        return 'AI Expand';
      case CloudAiFeature.backgroundGenerate:
        return 'AI Background';
      case CloudAiFeature.textToImage:
        return 'Text → Image';
    }
  }
}

/// Thrown when a cloud feature is invoked but no backend is configured (the
/// current state) or the user hasn't opted in.
class CloudAiUnavailable implements Exception {
  final String reason;
  const CloudAiUnavailable(this.reason);
  @override
  String toString() => 'CloudAiUnavailable: $reason';
}

/// Request/response contracts kept minimal and provider-agnostic.
class CloudAiRequest {
  final CloudAiFeature feature;
  final Uint8List? image; // source image (null for text→image)
  final Uint8List? mask; // for generative fill
  final String? prompt; // for generative features
  const CloudAiRequest({
    required this.feature,
    this.image,
    this.mask,
    this.prompt,
  });
}

abstract class CloudAiService {
  /// Whether a real backend is configured. The scaffold returns false.
  bool get isConfigured;

  /// Run a cloud AI feature. Implementations MUST require the caller to have
  /// confirmed the online-AI opt-in before calling.
  Future<Uint8List> run(CloudAiRequest request);
}

/// Default, shipped implementation: no backend, no network. Every call throws
/// [CloudAiUnavailable] so the UI can show a clear "coming soon / not
/// configured" message instead of silently failing or, worse, attempting a
/// network call this offline app can't and shouldn't make.
class DisabledCloudAiService implements CloudAiService {
  const DisabledCloudAiService();

  @override
  bool get isConfigured => false;

  @override
  Future<Uint8List> run(CloudAiRequest request) async {
    throw const CloudAiUnavailable(
      'Cloud AI is not configured. This build is offline-only; enabling it '
      'requires a backend + the INTERNET permission (see PLAN.md, Phase 10).',
    );
  }
}
