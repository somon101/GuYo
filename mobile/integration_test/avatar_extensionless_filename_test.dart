// Regression test for a real bug: a real Android gallery pick can hand
// back a content:// filename with NO extension at all -- the backend used
// to derive the stored file's own extension from that client-supplied
// filename, so an extensionless upload got stored with no extension
// either, and StaticFiles then had nothing to guess a Content-Type from on
// the way back out (served "text/plain" for a real photo). Image.network
// never surfaces that as a catchable Dart exception -- it just silently
// fails to render, which is exactly what "photo never changes, no error
// at all" looked like. The fix (app/routers/users.py's upload_my_avatar)
// derives the stored extension from the already-VALIDATED content_type
// instead, never the client's filename.
//
// Run with:
//   flutter test integration_test/avatar_extensionless_filename_test.dart -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
//
// Requires the local backend running at that URL, with user testuser/123456.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:guyo_app/api/api_client.dart';

// A minimal valid 1x1 PNG -- real image bytes, not a placeholder, so a real
// image codec genuinely has something to decode.
final _onePixelPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
  0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, 0x54, 0x78, 0xDA, 0x63, 0x60, 0x60, 0x00, 0x00,
  0x00, 0x02, 0x00, 0x01, 0x5D, 0xE5, 0xC8, 0xB7, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
  0xAE, 0x42, 0x60, 0x82,
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an avatar upload with an extensionless filename still serves back as a real image', (tester) async {
    await ApiClient.instance.login('testuser', '123456');

    // No mimeType hint AND no extension in the filename -- the exact
    // real-world combination that used to slip through as
    // application/octet-stream (fixed client-side) and then get stored
    // with no extension at all (fixed server-side, which THIS test covers).
    final profile = await ApiClient.instance.uploadMyAvatar(_onePixelPng, 'somephoto', mimeType: null);
    expect(profile.avatarUrl, isNotNull);

    final fetched = await http.get(Uri.parse(ApiClient.instance.mediaUrl(profile.avatarUrl!)));
    expect(fetched.statusCode, 200);
    expect(
      fetched.headers['content-type'],
      anyOf('image/png', 'image/jpeg', 'image/webp'),
      reason: 'must be a real image Content-Type, never text/plain -- that is what Image.network silently refused to render',
    );
    expect(fetched.bodyBytes, orderedEquals(_onePixelPng));

    await ApiClient.instance.deleteMyAvatar();
  });
}
