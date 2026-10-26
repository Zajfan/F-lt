class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.publishableKey,
    required this.demoMode,
  });

  factory AppConfig.fromEnvironment() => AppConfig(
        supabaseUrl: const String.fromEnvironment('FALT_SUPABASE_URL').trim(),
        publishableKey:
            const String.fromEnvironment('FALT_SUPABASE_PUBLISHABLE_KEY').trim(),
        demoMode: _parseBool(
          const String.fromEnvironment('FALT_DEMO_MODE'),
        ),
      );

  final String supabaseUrl;
  final String publishableKey;
  final bool demoMode;

  bool get isLive =>
      !demoMode && supabaseUrl.isNotEmpty && publishableKey.isNotEmpty;

  static bool _parseBool(String value) =>
      const {'1', 'true', 'yes', 'on'}.contains(value.trim().toLowerCase());
}
