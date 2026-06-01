/// App configuration. The backend base URL is injected at build/run time:
///   flutter run -d chrome --dart-define=BACKEND_BASE_URL=http://localhost:8080
class AppConfig {
  static const backendBaseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );
}
