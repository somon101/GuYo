import 'package:google_sign_in/google_sign_in.dart';

/// The Web OAuth client ID of GuYo's Google Cloud project (not a secret):
/// Google issues the ID token for it, and the backend accepts only tokens
/// issued for it (app/core/google_auth.py). Empty hides "Войти через Google".
const String googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID', defaultValue: '');

bool get googleSignInEnabled => googleWebClientId.isNotEmpty;

/// What the short Google sign-up starts from.
class GoogleSignup {
  final String idToken;
  final String email;
  final String? firstName;
  final String? lastName;

  const GoogleSignup({required this.idToken, required this.email, this.firstName, this.lastName});
}

bool _initialized = false;

/// Shows Google's account picker and returns the picked account's ID
/// token, or null if the user closed it.
Future<String?> pickGoogleIdToken() async {
  final signIn = GoogleSignIn.instance;
  if (!_initialized) {
    await signIn.initialize(serverClientId: googleWebClientId);
    _initialized = true;
  }
  // Always offer the account choice instead of silently reusing the last one.
  await signIn.signOut();
  try {
    final account = await signIn.authenticate();
    return account.authentication.idToken;
  } on GoogleSignInException catch (e) {
    if (e.code == GoogleSignInExceptionCode.canceled) return null;
    rethrow;
  }
}
