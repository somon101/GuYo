import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// «Собери слово» difficulty, chosen by the learner and remembered on the
/// phone: easy (default) shows a few letters already in place, hard is the
/// empty board. Only a comfort setting -- points, rating and progress are
/// the same either way.
final ValueNotifier<bool> buildWordEasy = ValueNotifier(true);

const _storage = FlutterSecureStorage();
const _key = 'build_word_easy';
bool _loaded = false;

Future<void> loadBuildWordMode() async {
  if (_loaded) return;
  _loaded = true;
  try {
    final saved = await _storage.read(key: _key);
    if (saved != null) buildWordEasy.value = saved == '1';
  } catch (_) {
    // Not essential: keep the default.
  }
}

Future<void> setBuildWordEasy(bool easy) async {
  buildWordEasy.value = easy;
  try {
    await _storage.write(key: _key, value: easy ? '1' : '0');
  } catch (_) {
    // Not essential.
  }
}

/// How many letters easy mode places for a word of [length] letters:
/// 1 → none, 2–3 → 1, 4–5 → 2, 6+ → 3.
int buildWordHintCount(int length) {
  if (length <= 1) return 0;
  if (length <= 3) return 1;
  if (length <= 5) return 2;
  return 3;
}
