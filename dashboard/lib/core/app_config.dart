class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  static const String _explicitWsUrl = String.fromEnvironment(
    'WS_URL',
    defaultValue: '',
  );

  static const bool publicDemoMode = bool.fromEnvironment(
    'PUBLIC_DEMO_MODE',
    defaultValue: false,
  );

  static String get wsUrl => _explicitWsUrl.isNotEmpty
      ? _explicitWsUrl
      : _webSocketUrlFrom(apiBaseUrl);

  static String _webSocketUrlFrom(String baseUrl) {
    final uri = Uri.parse(baseUrl);
    final scheme = switch (uri.scheme) {
      'https' => 'wss',
      'http' => 'ws',
      final value => value,
    };

    return uri.replace(scheme: scheme, path: '/ws').toString();
  }
}
