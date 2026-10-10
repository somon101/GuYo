import '../services/google_auth.dart';
import '../widgets/update_required.dart';
import '../screens/stats_screen.dart' show UserStats;
import '../services/session_cache.dart';
import '../l10n/l10n.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config.dart';
import '../models/status.dart';
import '../models/dictionary.dart';
import '../models/exercise.dart';
import '../models/learning.dart';
import '../models/lesson.dart';
import '../models/notification.dart';
import '../models/phrase.dart';
import '../models/premium.dart';
import '../models/quest.dart';
import '../models/user_profile.dart';
import '../models/user_rating.dart';
import '../models/word.dart';
import '../services/answer_signals.dart';

/// package:http's MultipartFile.fromBytes defaults to
/// application/octet-stream when no contentType is given -- the backend's
/// avatar/icon upload endpoints reject that (they only accept real image
/// MIME types), so every image upload from this client must set one
/// explicitly. [hint] is the platform's own reported MIME type for the
/// picked file (XFile.mimeType on image_picker results), which is far more
/// reliable than guessing from the filename -- some real Android gallery
/// apps hand back a content:// name with no recognizable extension at all,
/// which would otherwise silently fall through to octet-stream and get
/// rejected with no visible cause. Falls back to the filename's own
/// extension, and finally to JPEG -- every gallery/camera pick is some
/// raster photo, never truly "unknown".
MediaType _imageMediaType(String filename, {String? hint}) {
  MediaType? fromMime(String? mime) {
    if (mime == null) return null;
    switch (mime.toLowerCase()) {
      case 'image/png':
        return MediaType('image', 'png');
      case 'image/jpeg':
      case 'image/jpg':
        return MediaType('image', 'jpeg');
      case 'image/webp':
        return MediaType('image', 'webp');
      default:
        return null;
    }
  }

  final ext = filename.toLowerCase().split('.').last;
  final fromExtension = switch (ext) {
    'png' => MediaType('image', 'png'),
    'jpg' || 'jpeg' => MediaType('image', 'jpeg'),
    'webp' => MediaType('image', 'webp'),
    _ => null,
  };

  return fromMime(hint) ?? fromExtension ?? MediaType('image', 'jpeg');
}

/// GET /users/me/streak: the streak and the recent days with activity.
class StreakInfo {
  final int currentStreakDays;
  final DateTime today;
  final List<DateTime> activeDates;

  /// Missed days a weekly freeze covered: the streak survived them.
  final List<DateTime> frozenDates;
  const StreakInfo({
    required this.currentStreakDays,
    required this.today,
    required this.activeDates,
    this.frozenDates = const [],
  });
}

class ApiException implements Exception {
  final int? statusCode;
  final String message;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

/// Thin wrapper around the GuYo backend REST API. Holds the JWT in secure
/// storage (Android Keystore-backed) rather than plain SharedPreferences.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  final _storage = const FlutterSecureStorage();
  static const _tokenKey = 'guyo_user_token';

  String? _cachedToken;

  /// Bumped whenever the lesson counter may have changed (a lesson was
  /// just created). Главная's counter lives in another tab and listens to
  /// this instead of being reached into by whoever created the lesson.
  final ValueNotifier<int> lessonQuotaRevision = ValueNotifier<int>(0);

  Future<String?> get token async {
    _cachedToken ??= await _storage.read(key: _tokenKey);
    return _cachedToken;
  }

  Future<void> _saveToken(String token) async {
    _cachedToken = token;
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<void> clearToken() async {
    _cachedToken = null;
    await _storage.delete(key: _tokenKey);
  }

  Future<bool> get isLoggedIn async => (await token) != null;

  Uri _uri(String path) => Uri.parse('$apiBaseUrl$path');

  Future<Map<String, String>> _authHeaders() async {
    final t = await token;
    return {
      'Content-Type': 'application/json',
      'X-App-Build': '$appBuild',
      if (t != null) 'Authorization': 'Bearer $t',
    };
  }

  /// Returns full media URL for a relative path like "/media/....png".
  String mediaUrl(String relativePath) => '$apiBaseUrl$relativePath';

  Future<void> login(String login, String password) async {
    final res = await http.post(
      _uri('/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'login': login, 'password': password}),
    );
    if (res.statusCode == 401) {
      throw ApiException(tr('Неверный логин или пароль'), statusCode: 401);
    }
    if (res.statusCode != 200) {
      throw ApiException(tr('Ошибка сервера ({0})', [res.statusCode]), statusCode: res.statusCode);
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    await _saveToken(data['access_token'] as String);
    await _syncUiLanguage();
  }

  /// After login: a language picked on this device is saved to the account;
  /// otherwise the account's own language is applied here.
  Future<void> _syncUiLanguage() async {
    try {
      if (hasSavedAppLanguage) {
        await updateMyProfile(uiLanguage: appLanguage.value);
      } else {
        final profile = await fetchMyProfile();
        if (profile.uiLanguage != appLanguage.value) await setAppLanguage(profile.uiLanguage);
      }
    } catch (_) {}
  }

  /// One step of the learner's history (backend app/analytics/history.py):
  /// app_opened, lesson_opened/left, quest_opened/left. Fire-and-forget --
  /// a lost event must never disturb learning.
  void logEvent(String kind, {int? lessonId, int? questId, Map<String, Object>? data}) {
    () async {
      try {
        await http.post(
          _uri('/events'),
          headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
          body: jsonEncode({
            'kind': kind,
            if (lessonId != null) 'lesson_id': lessonId,
            if (questId != null) 'quest_id': questId,
            if (data != null) 'data': data,
          }),
        );
      } catch (_) {}
    }();
  }

  /// The server's own message from an error response, or [fallback].
  String _detailOf(http.Response res, String fallback) {
    try {
      final detail = (jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>)['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
    } catch (_) {}
    return fallback;
  }

  /// "Войти через Google" (backend POST /auth/google): logs in and returns
  /// null for a known Google account, or returns what the short sign-up
  /// needs for a new one.
  Future<GoogleSignup?> googleLogin(String idToken) async {
    final res = await http.post(
      _uri('/auth/google'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'id_token': idToken}),
    );
    if (res.statusCode != 200) {
      throw ApiException(_detailOf(res, tr('Ошибка сервера ({0})', [res.statusCode])), statusCode: res.statusCode);
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (data['needs_registration'] == true) {
      return GoogleSignup(
        idToken: idToken,
        email: data['email'] as String,
        firstName: data['first_name'] as String?,
        lastName: data['last_name'] as String?,
      );
    }
    await _saveToken(data['access_token'] as String);
    await _syncUiLanguage();
    return null;
  }

  /// Finishes the Google sign-up (backend POST /auth/google/register).
  Future<void> googleRegister({
    required String idToken,
    required String login,
    required String learningLanguage,
    required String ageGroup,
    required String learningGoal,
    List<String>? learningTopics,
    required String referralSource,
    String translationLanguage = 'tg',
  }) async {
    final res = await http.post(
      _uri('/auth/google/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'id_token': idToken,
        'login': login,
        'learning_language': learningLanguage,
        'age_group': ageGroup,
        'learning_goal': learningGoal,
        if (learningTopics != null) 'learning_topics': learningTopics,
        'referral_source': referralSource,
        'ui_language': appLanguage.value,
        'translation_language': translationLanguage,
      }),
    );
    if (res.statusCode != 201) {
      throw ApiException(_detailOf(res, tr('Ошибка сервера ({0})', [res.statusCode])), statusCode: res.statusCode);
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    await _saveToken(data['access_token'] as String);
  }

  Future<void> logout() async {
    SessionCache.clear();
    await clearToken();
  }

  /// The published-language list for the sign-up wizard's first step --
  /// reachable with no token at all (there is no account yet), unlike
  /// [fetchDictionaries] below which this deliberately does not touch or
  /// duplicate the logic of otherwise (same published-only list, just a
  /// route that doesn't require being logged in already -- see backend
  /// GET /dictionaries/public).
  Future<List<GuyoDictionary>> fetchPublicDictionaries() async {
    final res = await http.get(_uri('/dictionaries/public'), headers: {'Content-Type': 'application/json'});
    await _throwIfUnauthorized(res);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list.map((e) => GuyoDictionary.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Self-registration through the sign-up wizard -- creates the account
  /// and logs it in immediately, same token shape [login] itself saves.
  /// Throws with the backend's own message on conflict (login/email
  /// already taken).
  Future<void> register({
    required String login,
    required String password,
    required String passwordConfirm,
    required String firstName,
    required String lastName,
    required String idToken,
    required String learningLanguage,
    required String ageGroup,
    required String learningGoal,
    List<String>? learningTopics,
    required String referralSource,
    String translationLanguage = 'tg',
  }) async {
    final res = await http.post(
      _uri('/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'login': login,
        'password': password,
        'password_confirm': passwordConfirm,
        'first_name': firstName,
        'last_name': lastName,
        'id_token': idToken,
        'learning_language': learningLanguage,
        'age_group': ageGroup,
        'learning_goal': learningGoal,
        if (learningTopics != null) 'learning_topics': learningTopics,
        'referral_source': referralSource,
        'ui_language': appLanguage.value,
        'translation_language': translationLanguage,
      }),
    );
    await _throwWithDetail(res);
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    await _saveToken(data['access_token'] as String);
  }

  Future<List<GuyoDictionary>> fetchDictionaries() async {
    final res = await http.get(_uri('/dictionaries'), headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list.map((e) => GuyoDictionary.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<GuyoWord>> fetchWords(int dictionaryId) async {
    final res = await http.get(
      _uri('/dictionaries/$dictionaryId/words'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list.map((e) => GuyoWord.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// A 401 means this specific token is invalid/expired/for a deleted user
  /// -- never just a transient network hiccup. Left in secure storage, it
  /// would keep `isLoggedIn` reporting true forever (e.g. a token saved by
  /// an earlier debug build against a different backend), silently
  /// skipping the login screen on every future launch while every actual
  /// request keeps failing. Clearing it here means the very next app start
  /// -- or the explicit "Войти заново" this throws towards -- lands back
  /// on a real login instead of a dead retry loop.
  Future<void> _throwIfUnauthorized(http.Response res) async {
    if (res.statusCode == 426) {
      showUpdateRequired();
      throw ApiException(tr('Обновите приложение'), statusCode: res.statusCode);
    }
    if (res.statusCode == 401) {
      await clearToken();
      throw ApiException(tr('Сессия истекла, войдите снова'), statusCode: res.statusCode);
    }
    if (res.statusCode == 403) {
      throw ApiException(tr('Сессия истекла, войдите снова'), statusCode: res.statusCode);
    }
    if (res.statusCode >= 400) {
      throw ApiException(tr('Ошибка сервера ({0})', [res.statusCode]), statusCode: res.statusCode);
    }
  }

  /// Like [_throwIfUnauthorized], but for endpoints where the backend's
  /// `detail` message is meant to be shown to the user as-is (e.g. "Все
  /// доступные слова уже изучены") -- the backend is the source of truth
  /// for that wording, not a client-side copy of it.
  Future<void> _throwWithDetail(http.Response res) async {
    if (res.statusCode == 426) {
      showUpdateRequired();
      throw ApiException(tr('Обновите приложение'), statusCode: res.statusCode);
    }
    if (res.statusCode == 401) {
      await clearToken();
      throw ApiException(tr('Сессия истекла, войдите снова'), statusCode: res.statusCode);
    }
    if (res.statusCode == 403) {
      throw ApiException(tr('Сессия истекла, войдите снова'), statusCode: res.statusCode);
    }
    if (res.statusCode >= 400) {
      String message = tr('Ошибка сервера ({0})', [res.statusCode]);
      try {
        final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final detail = body['detail'];
        if (detail is String && detail.isNotEmpty) message = detail;
      } catch (_) {
        // Keep the generic message if the body isn't the expected shape.
      }
      throw ApiException(message, statusCode: res.statusCode);
    }
  }

  // --- Изучение слов ("Learning Words") ---------------------------------
  // Every method here just forwards to the backend, which is the sole
  // source of truth for session state -- nothing about the queue, random
  // selection or completion is decided on-device.

  /// Returns the current active (unfinished) learning session for this
  /// dictionary, or null if there isn't one -- distinct from an error.
  Future<LearningSession?> fetchActiveLearningSession(int dictionaryId) async {
    final res = await http.get(
      _uri('/learning/sessions/active?dictionary_id=$dictionaryId'),
      headers: await _authHeaders(),
    );
    if (res.statusCode == 404) return null;
    await _throwIfUnauthorized(res);
    return LearningSession.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<LearningSession> createLearningSession(int dictionaryId, int count) async {
    final res = await http.post(
      _uri('/learning/sessions'),
      headers: await _authHeaders(),
      body: jsonEncode({'dictionary_id': dictionaryId, 'count': count}),
    );
    await _throwWithDetail(res);
    return LearningSession.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<LearningSession> markWordLearned(int sessionId, int wordId) async {
    final res = await http.post(
      _uri('/learning/sessions/$sessionId/words/$wordId/learned'),
      headers: await _authHeaders(),
    );
    await _throwWithDetail(res);
    return LearningSession.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<LearningSession> markWordForReview(int sessionId, int wordId) async {
    final res = await http.post(
      _uri('/learning/sessions/$sessionId/words/$wordId/review'),
      headers: await _authHeaders(),
    );
    await _throwWithDetail(res);
    return LearningSession.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// [includeInProgress] widens "learned" to every word with ANY progress,
  /// not just fully-learned ones -- used only by learned_words_screen.dart
  /// ("Мои слова"). Defaults to false so build_phrase_screen.dart's own use
  /// of this endpoint (which needs fully-learned-only) is unaffected.
  Future<List<LearnedCategory>> fetchLearnedCategories(
    int dictionaryId, {
    bool includeInProgress = false,
  }) async {
    final params = {
      'dictionary_id': '$dictionaryId',
      if (includeInProgress) 'include_in_progress': 'true',
    };
    final uri = _uri('/learned-words/categories').replace(queryParameters: params);
    final res = await http.get(uri, headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list.map((e) => LearnedCategory.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// "Мои фразы": every Phrase in this dictionary whose every word is
  /// already learned (directly, or via one of that word's own forms) --
  /// entirely computed on the backend, never decided here. Not an
  /// exercise, no score, no progress of its own -- purely a live view over
  /// already-learned words and existing Phrase rows (see backend's
  /// list_available_phrases).
  Future<List<GuyoPhrase>> fetchAvailablePhrases(int dictionaryId) async {
    final res = await http.get(
      _uri('/dictionaries/$dictionaryId/available-phrases'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list.map((e) => GuyoPhrase.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Pass exactly one of [categoryId] or [uncategorized]; pass neither for
  /// every learned word in the dictionary regardless of category.
  /// [includeInProgress] -- see fetchLearnedCategories's own doc.
  Future<List<GuyoWord>> fetchLearnedWords(
    int dictionaryId, {
    int? categoryId,
    bool uncategorized = false,
    bool includeInProgress = false,
  }) async {
    final params = {
      'dictionary_id': '$dictionaryId',
      if (categoryId != null) 'category_id': '$categoryId',
      if (uncategorized) 'uncategorized': 'true',
      if (includeInProgress) 'include_in_progress': 'true',
    };
    final uri = _uri('/learned-words').replace(queryParameters: params);
    final res = await http.get(uri, headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list.map((e) => GuyoWord.fromJson(e as Map<String, dynamic>)).toList();
  }

  // --- Упражнения ("Exercises") ------------------------------------------
  // Word selection (learned-only) and the true/false decision are both
  // decided entirely on the backend -- this just fetches a ready round.

  Future<TrueOrFalseRound> fetchTrueOrFalseRound(int dictionaryId) async {
    final res = await http.get(
      _uri('/dictionaries/$dictionaryId/exercises/true-or-false'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return TrueOrFalseRound.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// The generic "N random already-learned words" round, capped by
  /// [exerciseKey]'s admin-configured count on the backend. Used by
  /// "Сопоставление" (exerciseKey "matching") in place of the old
  /// fetchWords(dictionaryId) call -- everything downstream of the word
  /// list (shuffling into two columns, tap-to-match) is unchanged.
  Future<List<GuyoWord>> fetchExerciseLearnedWords(int dictionaryId, String exerciseKey) async {
    final res = await http.get(
      _uri('/dictionaries/$dictionaryId/exercises/$exerciseKey/learned-words'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final list = body['words'] as List<dynamic>;
    return list.map((e) => GuyoWord.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<BuildWordRound> fetchBuildWordRound(int dictionaryId) async {
    final res = await http.get(
      _uri('/dictionaries/$dictionaryId/exercises/build-word'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return BuildWordRound.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  // --- Уроки ("Lessons") --------------------------------------------------
  // The new primary progress system: every word/score/threshold/completion
  // decision is made entirely by the backend (see backend/app/routers/
  // lessons.py) -- these methods only forward requests and parse responses.

  /// The full, permanent lesson history for this dictionary -- every lesson
  /// the user has ever created, oldest first, each with its current
  /// status. Powers the "Уроки" chain screen; unlike [fetchActiveLesson]
  /// this never means "not found", an empty list is a normal response for
  /// a user with no lessons yet.
  Future<List<LessonSummary>> fetchLessons(int dictionaryId) async {
    final res = await http.get(
      _uri('/dictionaries/$dictionaryId/lessons'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final list = body['lessons'] as List<dynamic>;
    return list.map((e) => LessonSummary.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<LessonCandidateWords> fetchLessonCandidateWords(int dictionaryId) async {
    final res = await http.get(
      _uri('/dictionaries/$dictionaryId/lesson-candidate-words'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return LessonCandidateWords.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// Returns the current active (not-yet-completed) lesson for this
  /// dictionary, or null if there isn't one -- distinct from an error, same
  /// convention as [fetchActiveLearningSession].
  Future<Lesson?> fetchActiveLesson(int dictionaryId) async {
    final res = await http.get(
      _uri('/lessons/active').replace(queryParameters: {'dictionary_id': '$dictionaryId'}),
      headers: await _authHeaders(),
    );
    if (res.statusCode == 404) return null;
    await _throwIfUnauthorized(res);
    return Lesson.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<Lesson> fetchLesson(int lessonId) async {
    final res = await http.get(_uri('/lessons/$lessonId'), headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    return Lesson.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// Statistics of the pass that just finished (answers, accuracy, per
  /// exercise, per-word score gain).
  Future<LessonPassStats> fetchLessonPassStats(int lessonId) async {
    final res = await http.get(_uri('/lessons/$lessonId/pass/stats'), headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    if (res.statusCode != 200) throw ApiException(tr('Статистика недоступна'), statusCode: res.statusCode);
    return LessonPassStats.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// Starts one pass through the lesson: the backend freezes the words
  /// still short of their level as the set every exercise of this pass
  /// uses, so each of them goes through every exercise even if it reaches
  /// its level halfway. Called at the start of every pass.
  /// The lesson whose pass is being played right now in LessonRunScreen.
  /// Its answers are held back on the server and only count once the pass
  /// is finished ([finishLessonPass]); leaving mid-pass counts nothing.
  int? deferredLessonId;

  /// The pass was played to the end: its answers count now.
  Future<void> finishLessonPass(int lessonId) async {
    final res = await http.post(_uri('/lessons/$lessonId/pass/finish'), headers: await _authHeaders());
    await _throwWithDetail(res);
  }

  Future<Lesson> startLessonPass(int lessonId) async {
    final res = await http.post(_uri('/lessons/$lessonId/pass'), headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    return Lesson.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// Pass exactly one of [wordIds] (ручной выбор, max 15) or [randomCount]
  /// (случайный выбор, 1-15) -- the backend rejects both/neither, same rule
  /// CreateLessonIn enforces. Fails with a 409 (surfaced via [ApiException.
  /// message]) if the current lesson for this dictionary isn't complete yet,
  /// or a 429 once the daily/weekly lesson limit is reached.
  Future<Lesson> createLesson({required int dictionaryId, List<int>? wordIds, int? randomCount}) async {
    final res = await http.post(
      _uri('/lessons'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'dictionary_id': dictionaryId,
        if (wordIds != null) 'word_ids': wordIds,
        if (randomCount != null) 'random_count': randomCount,
      }),
    );
    await _throwWithDetail(res);
    lessonQuotaRevision.value++;
    return Lesson.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<TrueOrFalseRound> fetchLessonTrueOrFalseRound(int lessonId) async {
    final res = await http.get(
      _uri('/lessons/$lessonId/exercises/true-or-false'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return TrueOrFalseRound.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// Same generic shape as [fetchExerciseLearnedWords], sourced from this
  /// lesson's fixed word set instead of the dictionary's learned words.
  Future<List<GuyoWord>> fetchLessonMatchingWords(int lessonId) async {
    final res = await http.get(
      _uri('/lessons/$lessonId/exercises/matching'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final list = body['words'] as List<dynamic>;
    return list.map((e) => GuyoWord.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<BuildWordRound> fetchLessonBuildWordRound(int lessonId) async {
    final res = await http.get(
      _uri('/lessons/$lessonId/exercises/build-word'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return BuildWordRound.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<SpeakingWordRound> fetchLessonSpeakingWordRound(int lessonId) async {
    final res = await http.get(
      _uri('/lessons/$lessonId/exercises/speaking-word'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return SpeakingWordRound.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<ListenWordRound> fetchLessonListenWordRound(int lessonId) async {
    final res = await http.get(
      _uri('/lessons/$lessonId/exercises/listen-word'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return ListenWordRound.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  // --- Практика ------------------------------------------------------------
  // Self-directed rounds over "Мои изученные слова" for the same 5 exercise
  // types Уроки/Квесты already offer -- the backend randomly samples from
  // the user's own learned-word pool and returns a round in the EXACT SAME
  // shape a Lesson round does (backend/app/routers/practice.py concatenates
  // Quest's own single-word round builders), so these parse into the exact
  // same models fetchLessonXRound already returns. Nothing here ever
  // reports an answer back -- Practice keeps no score of its own, same as
  // fetchAvailablePhrases/fetchLearnedWords already established.

  Future<TrueOrFalseRound> fetchPracticeTrueOrFalseRound(int dictionaryId) async {
    final res = await http.get(
      _uri('/dictionaries/$dictionaryId/practice/true-or-false'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return TrueOrFalseRound.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<List<GuyoWord>> fetchPracticeMatchingWords(int dictionaryId) async {
    final res = await http.get(
      _uri('/dictionaries/$dictionaryId/practice/matching'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final list = body['words'] as List<dynamic>;
    return list.map((e) => GuyoWord.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// "Повторить сегодня": how many learned words are being forgotten, and
  /// the most forgotten ones (GET .../practice/review-due).
  Future<(int, List<int>)> fetchReviewDue(int dictionaryId) async {
    final res = await http.get(_uri('/dictionaries/$dictionaryId/practice/review-due'), headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return (json['count'] as int, [for (final id in json['word_ids'] as List<dynamic>) id as int]);
  }

  Future<BuildWordRound> fetchPracticeBuildWordRound(int dictionaryId, {List<int>? wordIds}) async {
    final uri = _uri('/dictionaries/$dictionaryId/practice/build-word');
    final res = await http.get(
      wordIds == null || wordIds.isEmpty
          ? uri
          : uri.replace(queryParameters: {'word_ids': [for (final id in wordIds) '$id']}),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return BuildWordRound.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<SpeakingWordRound> fetchPracticeSpeakingWordRound(int dictionaryId) async {
    final res = await http.get(
      _uri('/dictionaries/$dictionaryId/practice/speaking-word'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return SpeakingWordRound.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<ListenWordRound> fetchPracticeListenWordRound(int dictionaryId) async {
    final res = await http.get(
      _uri('/dictionaries/$dictionaryId/practice/listen-word'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return ListenWordRound.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// The one call that actually changes anything in the Уроки system: moves
  /// [wordId]'s score by [exerciseKey]'s admin-configured points (backend
  /// decides direction/amount/clamping/threshold -- never this client) and
  /// reports whether the word, and then the whole lesson, just got learned.
  Future<SubmitAnswerResult> submitLessonAnswer(
    int lessonId,
    String exerciseKey, {
    required int wordId,
    required bool isCorrect,
  }) async {
    final signals = AnswerSignals.take();
    final res = await http.post(
      _uri('/lessons/$lessonId/exercises/$exerciseKey/answers'),
      headers: await _authHeaders(),
      body: jsonEncode({
        ...signals,
        'word_id': wordId,
        'is_correct': isCorrect,
        if (deferredLessonId == lessonId) 'deferred': true,
      }),
    );
    await _throwWithDetail(res);
    return SubmitAnswerResult.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  // --- Профиль и Достижения ------------------------------------------------
  // Avatar storage and achievement earning/eligibility are entirely
  // backend-decided (see backend/app/achievements/) -- this client only
  // fetches/uploads and renders the result.

  Future<UserProfile> fetchMyProfile() async {
    final res = await http.get(_uri('/users/me/profile'), headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    return UserProfile.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  // --- Слоганы и уведомления ------------------------------------------

  /// This user's greeting line for today.
  ///
  /// The backend draws it once per day and holds it, so calling this again
  /// the same day returns the same line (see backend/app/slogans/). Null
  /// when an admin has no enabled slogans at all -- the caller falls back
  /// to the app's own built-in line rather than greeting with a blank row.
  Future<String?> fetchTodaySlogan() async {
    final res = await http.get(_uri('/slogans/today'), headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return body['text'] as String?;
  }

  /// Premium status, the payment text the admin wrote, and today's/this
  /// week's lesson counter -- everything Главная's counter and the Premium
  /// screen show, in one call.
  Future<PremiumStatus> fetchPremiumStatus() async {
    final res = await http.get(_uri('/premium/me'), headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    return PremiumStatus.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// Activates a promo code or a pasted video link -- one field for both,
  /// the backend tells them apart. Fails with the backend's own message
  /// (no such code, already used, expired...).
  Future<PromoResult> redeemPromo(String code) async {
    final res = await http.post(
      _uri('/promo/redeem'),
      headers: await _authHeaders(),
      body: jsonEncode({'code': code}),
    );
    await _throwWithDetail(res);
    // Premium may have just started, lifting the lesson limit.
    lessonQuotaRevision.value++;
    return PromoResult.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// Everything in this user's inbox, newest first, with the unread count
  /// the bell's dot is drawn from.
  Future<NotificationInbox> fetchNotifications() async {
    final res = await http.get(_uri('/notifications'), headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    return NotificationInbox.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// One Practice answer, recorded as memory evidence only: Practice
  /// changes no score. Fire-and-forget from the caller's point of view.
  Future<void> submitPracticeAnswer(
    int dictionaryId, {
    required String exerciseKey,
    required int wordId,
    required bool isCorrect,
  }) async {
    final signals = AnswerSignals.take();
    final res = await http.post(
      _uri('/dictionaries/$dictionaryId/practice/answers'),
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({...signals, 'word_id': wordId, 'exercise_key': exerciseKey, 'is_correct': isCorrect}),
    );
    await _throwIfUnauthorized(res);
  }

  /// Tells the server which phone to send this user's pushes to.
  Future<void> registerPushToken(String pushToken) async {
    final res = await http.post(
      _uri('/notifications/push-token'),
      headers: await _authHeaders(),
      body: jsonEncode({'token': pushToken}),
    );
    await _throwIfUnauthorized(res);
  }

  Future<void> unregisterPushToken(String pushToken) async {
    final res = await http.delete(
      _uri('/notifications/push-token'),
      headers: await _authHeaders(),
      body: jsonEncode({'token': pushToken}),
    );
    await _throwIfUnauthorized(res);
  }

  /// Just the number behind the bell's dot -- its own call so the app bar
  /// never pulls the whole inbox to decide whether to show one.
  Future<int> fetchUnreadNotificationCount() async {
    final res = await http.get(_uri('/notifications/unread-count'), headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return body['unread_count'] as int;
  }

  /// Marks every message read and returns the refreshed inbox.
  Future<NotificationInbox> markAllNotificationsRead() async {
    final res = await http.post(_uri('/notifications/read-all'), headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    return NotificationInbox.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  // --- Профиль ---------------------------------------------------------

  /// Saves the fields the "Настройки" screen edits. Only what is passed
  /// is sent, and only what is sent is changed -- editing one field never
  /// blanks another. The photo is not here: it is a file and has its own
  /// upload/delete calls below.
  Future<UserProfile> updateMyProfile({
    String? login,
    String? firstName,
    String? lastName,
    String? email,
    List<String>? learningTopics,
    String? uiLanguage,
    String? translationLanguage,
  }) async {
    final body = <String, dynamic>{
      if (login != null) 'login': login,
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (email != null) 'email': email,
      if (learningTopics != null) 'learning_topics': learningTopics,
      if (uiLanguage != null) 'ui_language': uiLanguage,
      if (translationLanguage != null) 'translation_language': translationLanguage,
    };
    final res = await http.patch(
      _uri('/users/me/profile'),
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    // _throwWithDetail, not the plain check: a taken login or email comes
    // back as a 409 whose own message is the only useful thing to show.
    await _throwWithDetail(res);
    return UserProfile.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// Uploads [bytes] (read from whatever the user picked) as the new
  /// avatar, replacing any existing one -- the backend rejects anything
  /// that isn't a real, reasonably sized image rather than this client
  /// pre-guessing what's valid.
  ///
  /// [req.send] has an explicit timeout -- without one, a stalled/flaky
  /// mobile connection left this Future waiting forever with no error and
  /// no way for the UI to ever leave its "uploading" state, which looked
  /// exactly like a permanent freeze.
  Future<UserProfile> uploadMyAvatar(List<int> bytes, String filename, {String? mimeType}) async {
    final t = await token;
    final req = http.MultipartRequest('POST', _uri('/users/me/avatar'))
      ..headers['Authorization'] = 'Bearer $t'
      ..files.add(
        http.MultipartFile.fromBytes(
          'avatar',
          bytes,
          filename: filename,
          contentType: _imageMediaType(filename, hint: mimeType),
        ),
      );
    final streamed = await req.send().timeout(
      const Duration(seconds: 25),
      onTimeout: () => throw ApiException(tr('Загрузка не удалась: слишком медленное соединение')),
    );
    final res = await http.Response.fromStream(streamed).timeout(const Duration(seconds: 25));
    await _throwWithDetail(res);
    return UserProfile.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// Clears the avatar -- the caller should fall back to the generated
  /// default avatar the moment `avatarUrl` comes back null.
  Future<UserProfile> deleteMyAvatar() async {
    final res = await http
        .delete(_uri('/users/me/avatar'), headers: await _authHeaders())
        .timeout(const Duration(seconds: 15));
    await _throwIfUnauthorized(res);
    return UserProfile.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<List<UserAchievement>> fetchMyAchievements() async {
    final res = await http.get(_uri('/users/me/achievements'), headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list.map((e) => UserAchievement.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// The Статистика screen's data (GET /users/me/stats), for a 7 or 30 day chart.
  Future<UserStats> fetchMyStats(int days) async {
    final res = await http.get(
      _uri('/users/me/stats').replace(queryParameters: {'days': '$days'}),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    if (res.statusCode != 200) throw ApiException('Не удалось загрузить статистику', statusCode: res.statusCode);
    return UserStats.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// Earned but not yet shown to this account (GET /users/me/achievements/new).
  Future<List<UserAchievement>> fetchNewAchievements() async {
    final res = await http.get(_uri('/users/me/achievements/new'), headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    if (res.statusCode != 200) throw ApiException('Не удалось загрузить достижения', statusCode: res.statusCode);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list.map((e) => UserAchievement.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Records on the server that these achievements were celebrated.
  Future<void> markAchievementsSeen(List<int> ids) async {
    final res = await http.post(
      _uri('/users/me/achievements/seen'),
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({'ids': ids}),
    );
    await _throwIfUnauthorized(res);
    if (res.statusCode >= 300) throw ApiException('Не удалось сохранить', statusCode: res.statusCode);
  }

  /// A fully separate system from achievements (see backend/app/rating/) --
  /// current points, current season, current rank and season history, all
  /// backend-decided.
  Future<UserRating> fetchMyRating() async {
    final res = await http.get(_uri('/users/me/rating'), headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    return UserRating.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// Top 100 users sharing the CALLER's own current rank -- the backend
  /// decides which rank that is; there is no way to ask for a different
  /// one.
  Future<Leaderboard> fetchMyRankLeaderboard() async {
    final res = await http.get(_uri('/rating/leaderboard'), headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    return Leaderboard.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// The word-reinforcement ladder, enabled levels only, lowest
  /// score-range first -- see WordLevelSummary's own doc.
  Future<List<WordLevelSummary>> fetchWordLevels() async {
    final res = await http.get(_uri('/word-levels'), headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list.map((e) => WordLevelSummary.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// What the status picker offers, plus the user's current status.
  Future<StatusOptions> fetchStatusOptions() async {
    final res = await http.get(_uri('/status/options'), headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    if (res.statusCode != 200) throw ApiException(tr('Не удалось загрузить статусы'), statusCode: res.statusCode);
    return StatusOptions.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// Sets both parts of the leaderboard status; null clears a part.
  Future<MyStatus> updateMyStatus({int? emojiId, int? phraseId}) async {
    final res = await http.put(
      _uri('/status/me'),
      headers: await _authHeaders(),
      body: jsonEncode({'emoji_id': emojiId, 'phrase_id': phraseId}),
    );
    await _throwIfUnauthorized(res);
    if (res.statusCode != 200) throw ApiException(tr('Не удалось сохранить статус'), statusCode: res.statusCode);
    return MyStatus.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// Top 100 users across every rank combined.
  Future<Leaderboard> fetchGlobalLeaderboard() async {
    final res = await http.get(_uri('/rating/leaderboard/global'), headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    return Leaderboard.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// The full rank ladder, enabled ranks only, lowest points-requirement
  /// first -- what the Profile screen's "Все уровни" full-progress-path
  /// screen renders. The SAME ranks/order fetchMyRating's own rank/
  /// next_rank came from, never a second definition of the ladder.
  Future<List<RankSummary>> fetchAllRanks() async {
    final res = await http.get(_uri('/rating/ranks'), headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list.map((e) => RankSummary.fromJson(e as Map<String, dynamic>)).toList();
  }

  // --- Квесты ---------------------------------------------------------------
  // A system entirely separate from Lessons (see backend/app/quests/) --
  // eligibility, round content, and reward are all backend-decided.

  Future<List<AvailableQuest>> fetchAvailableQuests(int dictionaryId) async {
    final res = await http.get(
      _uri('/quests').replace(queryParameters: {'dictionary_id': '$dictionaryId'}),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list.map((e) => AvailableQuest.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Everything the "Квесты сезона" block on Главная and the season
  /// quests screen need, in one round trip -- the active season with its
  /// admin-uploaded icon, this user's rating standing, and their quest
  /// progress today. A read-only view over the season/rating/quest
  /// systems that already exist; nothing here is a second source of any
  /// of those numbers.
  Future<SeasonQuestOverview> fetchSeasonQuestOverview(int dictionaryId) async {
    final res = await http.get(
      _uri('/quests/overview').replace(queryParameters: {'dictionary_id': '$dictionaryId'}),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return SeasonQuestOverview.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// Today's points, grant by grant, newest first (GET /quests/points-today).
  Future<List<PointsTodayItem>> fetchPointsToday() async {
    final res = await http.get(_uri('/quests/points-today'), headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    if (res.statusCode != 200) throw ApiException('Не удалось загрузить историю', statusCode: res.statusCode);
    return (jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>)
        .map((e) => PointsTodayItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The streak sheet's data (GET /users/me/streak).
  Future<StreakInfo> fetchMyStreak() async {
    final res = await http.get(_uri('/users/me/streak'), headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    if (res.statusCode != 200) throw ApiException('Не удалось загрузить серию', statusCode: res.statusCode);
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    DateTime day(String s) {
      final d = DateTime.parse(s);
      return DateTime(d.year, d.month, d.day);
    }

    return StreakInfo(
      currentStreakDays: json['current_streak_days'] as int,
      today: day(json['today'] as String),
      activeDates: [for (final s in json['active_dates'] as List<dynamic>) day(s as String)],
      frozenDates: [for (final s in (json['frozen_dates'] as List<dynamic>? ?? const [])) day(s as String)],
    );
  }

  Future<QuestRound> fetchQuestRound(int questId, int dictionaryId) async {
    final res = await http.get(
      _uri('/quests/$questId/round').replace(queryParameters: {'dictionary_id': '$dictionaryId'}),
      headers: await _authHeaders(),
    );
    await _throwWithDetail(res);
    return QuestRound.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<QuestAnswerResult> submitQuestAnswer(
    int questId,
    int dictionaryId, {
    required int wordId,
    required bool isCorrect,
  }) async {
    final signals = AnswerSignals.take();
    final res = await http.post(
      _uri('/quests/$questId/answers').replace(queryParameters: {'dictionary_id': '$dictionaryId'}),
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({...signals, 'word_id': wordId, 'is_correct': isCorrect}),
    );
    await _throwWithDetail(res);
    return QuestAnswerResult.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }
}
