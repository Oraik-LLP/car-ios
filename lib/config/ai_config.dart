/// Client-safe AI configuration.
/// The app talks to a backend that owns Gemini credentials.
abstract final class AiConfig {
  static const backendUrl = String.fromEnvironment(
    'AI_BACKEND_URL',
    defaultValue: 'https://api.fixease.oraik.co',
  );

  static bool get isConfigured => backendUrl.isNotEmpty;

  static const diagnosisModel = 'gemini-flash-latest';
  static const liveModel = 'gemini-3.1-flash-live-preview';

  static Uri endpoint(String path) {
    final base = backendUrl.endsWith('/')
        ? backendUrl.substring(0, backendUrl.length - 1)
        : backendUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$normalizedPath');
  }
}
