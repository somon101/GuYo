/// Backend base URL.
///
/// Overridden at build time with:
///   flutter build apk --dart-define=API_BASE_URL=https://your-backend.example.com
///
/// Defaults to 10.0.2.2, which is how the Android emulator reaches the
/// host machine's localhost -- convenient for local development against
/// `uvicorn` running on the dev machine. A real device needs either the
/// dart-define above or the LAN IP of the dev machine.
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

/// This build's number -- the same as the "+N" of `version:` in
/// pubspec.yaml (keep them equal when releasing). Sent with every request
/// as X-App-Build, so the server can ask outdated apps to update (its
/// MIN_APP_BUILD setting).
const int appBuild = 2;
