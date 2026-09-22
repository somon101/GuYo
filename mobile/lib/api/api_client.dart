import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config.dart';
import '../models/dictionary.dart';
import '../models/exercise.dart';
import '../models/learning.dart';
import '../models/lesson.dart';
import '../models/phrase.dart';
import '../models/quest.dart';
import '../models/user_profile.dart';
import '../models/user_rating.dart';
import '../models/word.dart';

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
      throw ApiException('Неверный логин или пароль', statusCode: 401);
    }
    if (res.statusCode != 200) {
      throw ApiException('Ошибка сервера (${res.statusCode})', statusCode: res.statusCode);
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    await _saveToken(data['access_token'] as String);
  }

  Future<void> logout() async {
    await clearToken();
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
    if (res.statusCode == 401) {
      await clearToken();
      throw ApiException('Сессия истекла, войдите снова', statusCode: res.statusCode);
    }
    if (res.statusCode == 403) {
      throw ApiException('Сессия истекла, войдите снова', statusCode: res.statusCode);
    }
    if (res.statusCode >= 400) {
      throw ApiException('Ошибка сервера (${res.statusCode})', statusCode: res.statusCode);
    }
  }

  /// Like [_throwIfUnauthorized], but for endpoints where the backend's
  /// `detail` message is meant to be shown to the user as-is (e.g. "Все
  /// доступные слова уже изучены") -- the backend is the source of truth
  /// for that wording, not a client-side copy of it.
  Future<void> _throwWithDetail(http.Response res) async {
    if (res.statusCode == 401) {
      await clearToken();
      throw ApiException('Сессия истекла, войдите снова', statusCode: res.statusCode);
    }
    if (res.statusCode == 403) {
      throw ApiException('Сессия истекла, войдите снова', statusCode: res.statusCode);
    }
    if (res.statusCode >= 400) {
      String message = 'Ошибка сервера (${res.statusCode})';
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

  /// Pass exactly one of [wordIds] (ручной выбор, max 15) or [randomCount]
  /// (случайный выбор, 1-15) -- the backend rejects both/neither, same rule
  /// CreateLessonIn enforces. Fails with a 409 (surfaced via [ApiException.
  /// message]) if the current lesson for this dictionary isn't complete yet.
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
    final res = await http.post(
      _uri('/lessons/$lessonId/exercises/$exerciseKey/answers'),
      headers: await _authHeaders(),
      body: jsonEncode({'word_id': wordId, 'is_correct': isCorrect}),
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
      onTimeout: () => throw ApiException('Загрузка не удалась: слишком медленное соединение'),
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

  /// Top 100 users across every rank combined.
  Future<Leaderboard> fetchGlobalLeaderboard() async {
    final res = await http.get(_uri('/rating/leaderboard/global'), headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    return Leaderboard.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
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
    final res = await http.post(
      _uri('/quests/$questId/answers').replace(queryParameters: {'dictionary_id': '$dictionaryId'}),
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({'word_id': wordId, 'is_correct': isCorrect}),
    );
    await _throwWithDetail(res);
    return QuestAnswerResult.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }
}
