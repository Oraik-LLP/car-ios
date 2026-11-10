/// Local feature-flag service.
/// Backed by in-memory defaults today; swap for remote config later.
abstract final class FeatureFlags {
  static final Map<String, bool> _overrides = {};

  // ── flags ──────────────────────────────────────────────────────────────
  static bool get geminiLiveBeta => _get('gemini_live_beta', false);
  static bool get photoUploadEnabled => _get('photo_upload', true);
  static bool get subscriptionEnabled => _get('subscription', false);
  static bool get offlineDiagnostics => _get('offline_diagnostics', false);

  // ── helpers ────────────────────────────────────────────────────────────
  static bool _get(String key, bool fallback) =>
      _overrides[key] ?? fallback;

  static void override(String key, bool value) => _overrides[key] = value;
  static void clearOverrides() => _overrides.clear();
}
