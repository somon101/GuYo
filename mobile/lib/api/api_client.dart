import '../services/streak_state.dart';
import 'dart:async';
import '../services/google_auth.dart';
import '../services/disk_cache.dart';
import '../widgets/study_times_editor.dart' show StudyTime;
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
import '../models/exercise_scoring.dart';
import '../models/learning.dart';
import '../models/lesson.dart';
import '../models/notification.dart';
import '../models/mini_phrase.dart';
import '../models/phrase.dart';
import '../models/premium.dart';
import '../models/quest.dart';
import '../models/text_check.dart';
import '../models/user_profile.dart';
import '../models/user_rating.dart';
import '../models/word.dart';
import '../services/answer_signals.dart';
import '../services/lesson_scoring.dart';
import '../services/pending_answers.dart';

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

/// Someone found by their 9-digit ID.
class FoundUser {
  final int userId;
  final int publicId;
  final String login;
  final String name;
  final String? avatarUrl;
  final int totalPoints;
  final bool isMe;
  final bool isFriend;

  FoundUser.fromJson(Map<String, dynamic> j)
      : userId = j['user_id'] as int,
        publicId = j['public_id'] as int,
        login = j['login'] as String,
        name = j['name'] as String,
        avatarUrl = j['avatar_url'] as String?,
        totalPoints = j['total_points'] as int,
        isMe = j['is_me'] as bool,
        isFriend = j['is_friend'] as bool;
}

class ApiException implements Exception {
  final int? statusCode;
  final String message;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

/// How long an action that decides whether a pass can be played at all (opening
/// a pass, closing one) waits for the network before giving up and being queued
/// on the device instead.
///
/// It MUST be short: with no network the request would otherwise sit on the
/// operating system's own timeout for tens of seconds, and the user pressing
/// «Продолжить» on a lesson they prepared earlier would watch a frozen screen
/// instead of the lesson. Everything these calls do is queued and retried when
/// there is a connection, so giving up early costs nothing.
const Duration kOfflineActionTimeout = Duration(seconds: 5);

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
    // A fresh login may be a different account: start with nothing kept.
    SessionCache.clear();
    await DiskCache.clear();
    _cachedToken = token;
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<void> clearToken() async {
    // Last chance to deliver answers judged on this device: they belong to the
    // account that is about to leave, and nothing else would ever resend them.
    await flushPendingAnswers();
    _cachedToken = null;
    // Whatever was kept belongs to the account that just left.
    SessionCache.clear();
    await DiskCache.clear();
    await PendingAnswers.clear();
    await _storage.delete(key: _tokenKey);
  }

  Future<bool> get isLoggedIn async => (await token) != null;

  Uri _uri(String path) => Uri.parse('$apiBaseUrl$path');

  Future<Map<String, String>> _authHeaders() async {
    final t = await token;
    return {
      'Content-Type': 'application/json',
      'X-App-Build': '$appBuild',
      // Content comes in the language on screen right away, even before a
      // just-changed interface language is saved to the profile.
      'X-UI-Language': appLanguage.value,
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

  /// A Практика round played to the end: lights today's streak day
  /// (backend POST .../practice/finish). Fire-and-forget.
  void finishPractice(int dictionaryId) {
    () async {
      try {
        final res = await http.post(_uri('/dictionaries/$dictionaryId/practice/finish'), headers: await _authHeaders());
        if (res.statusCode == 200) reportStreakResult(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
      } catch (_) {}
    }();
  }

  Future<void> logout() async {
    SessionCache.clear();
    await DiskCache.clear();
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
    // OPTIONAL: signing up does not require a Google account. Many people in our
    // market have none, or will not link one just to try an app -- and demanding it
    // here rejected them before they ever saw a lesson. Google can be connected
    // later from Settings (see linkGoogle).
    String? idToken,
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
        if (idToken != null) 'id_token': idToken,
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

  /// Connects a Google account to the account that is already signed in -- from
  /// Settings, after the fact. Signing up does not require one (see register).
  Future<void> linkGoogle(String idToken) async {
    final res = await http.post(
      _uri('/auth/google/link'),
      headers: await _authHeaders(),
      body: jsonEncode({'id_token': idToken}),
    );
    await _throwWithDetail(res);
  }

  Future<List<GuyoDictionary>> fetchDictionaries() async {
    final res = await http.get(_uri('/dictionaries'), headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    return _parseDictionaries(_remember('dictionaries', res));
  }

  List<GuyoDictionary> _parseDictionaries(dynamic json) =>
      (json as List<dynamic>).map((e) => GuyoDictionary.fromJson(e as Map<String, dynamic>)).toList();

  List<GuyoWord> _parseMatchingWords(dynamic json) => ((json as Map<String, dynamic>)['words'] as List<dynamic>)
      .map((e) => GuyoWord.fromJson(e as Map<String, dynamic>))
      .toList();

  // --- Last answers kept on the device (DiskCache) ---------------------
  // Each main screen opens on these and refreshes in the background.

  dynamic _remember(String key, http.Response res) {
    final body = utf8.decode(res.bodyBytes);
    DiskCache.put(key, body);
    return jsonDecode(body);
  }

  T? _cached<T>(String key, T Function(dynamic json) parse) {
    final body = DiskCache.get(key);
    if (body == null) return null;
    try {
      return parse(jsonDecode(body));
    } catch (_) {
      return null; // an older shape after an update -- just load fresh
    }
  }

  List<GuyoDictionary>? cachedDictionaries() => _cached('dictionaries', _parseDictionaries);
  SeasonQuestOverview? cachedSeasonQuestOverview(int dictionaryId) =>
      _cached('overview-$dictionaryId', (j) => SeasonQuestOverview.fromJson(j as Map<String, dynamic>));
  UserProfile? cachedMyProfile() => _cached('profile', (j) => UserProfile.fromJson(j as Map<String, dynamic>));
  List<UserAchievement>? cachedMyAchievements() => _cached(
      'achievements', (j) => (j as List<dynamic>).map((e) => UserAchievement.fromJson(e as Map<String, dynamic>)).toList());
  UserRating? cachedMyRating() => _cached('rating', (j) => UserRating.fromJson(j as Map<String, dynamic>));
  List<LessonSummary>? cachedLessons(int dictionaryId) => _cached(
      'lessons-$dictionaryId',
      (j) => _withLocalProgress(((j as Map<String, dynamic>)['lessons'] as List<dynamic>)
          .map((e) => LessonSummary.fromJson(e as Map<String, dynamic>))
          .toList()));
  Leaderboard? cachedMyRankLeaderboard() =>
      _cached('leaderboard', (j) => Leaderboard.fromJson(j as Map<String, dynamic>));
  List<GuyoWord>? cachedLearnedWords(int dictionaryId, {bool includeInProgress = false}) =>
      _cached('learned-words-$dictionaryId-$includeInProgress', _parseWords);
  List<LearnedCategory>? cachedLearnedCategories(int dictionaryId, {bool includeInProgress = false}) =>
      _cached('learned-categories-$dictionaryId-$includeInProgress', _parseLearnedCategories);
  List<WordLevelSummary>? cachedWordLevels() => _cached('word-levels', _parseWordLevels);
  List<RankSummary>? cachedAllRanks() => _cached('ranks', _parseRanks);
  StreakInfo? cachedMyStreak() => _cached('streak', _parseStreak);
  List<StudyTime>? cachedStudyTimes() => _cached('study-times', _parseStudyTimes);

  List<StudyTime> _parseStudyTimes(dynamic json) => [
        for (final t in (json as Map<String, dynamic>)['times'] as List<dynamic>)
          StudyTime.fromJson(t as Map<String, dynamic>),
      ];

  /// Drops what was kept for instant screens -- after a language change
  /// it is all in the old language. Screens then load fresh once.
  void forgetCachedContent() {
    SessionCache.clear();
    DiskCache.clear();
  }

  List<GuyoWord> _parseWords(dynamic json) =>
      (json as List<dynamic>).map((e) => GuyoWord.fromJson(e as Map<String, dynamic>)).toList();
  List<LearnedCategory> _parseLearnedCategories(dynamic json) =>
      (json as List<dynamic>).map((e) => LearnedCategory.fromJson(e as Map<String, dynamic>)).toList();
  List<WordLevelSummary> _parseWordLevels(dynamic json) =>
      (json as List<dynamic>).map((e) => WordLevelSummary.fromJson(e as Map<String, dynamic>)).toList();
  List<RankSummary> _parseRanks(dynamic json) =>
      (json as List<dynamic>).map((e) => RankSummary.fromJson(e as Map<String, dynamic>)).toList();

  StreakInfo _parseStreak(dynamic json) {
    final map = json as Map<String, dynamic>;
    DateTime day(String s) {
      final d = DateTime.parse(s);
      return DateTime(d.year, d.month, d.day);
    }

    return StreakInfo(
      currentStreakDays: map['current_streak_days'] as int,
      today: day(map['today'] as String),
      activeDates: [for (final s in map['active_dates'] as List<dynamic>) day(s as String)],
      frozenDates: [for (final s in (map['frozen_dates'] as List<dynamic>? ?? const [])) day(s as String)],
    );
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
    return _parseLearnedCategories(_remember('learned-categories-$dictionaryId-$includeInProgress', res));
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

  /// Практика: mini-phrases this user has already gone through in a lesson.
  Future<List<MiniPhrase>> fetchOpenMiniPhrases(int dictionaryId) async {
    final res = await http.get(
      _uri('/dictionaries/$dictionaryId/mini-phrases/open'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    if (res.statusCode != 200) throw ApiException(tr('Не удалось загрузить мини-фразы'));
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list.map((e) => MiniPhrase.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// A "Собери фразу" answer for a mini-phrase. The app already judged it
  /// locally (the right answer is known), so this goes out in the
  /// background and never makes anyone wait; the server re-checks it and
  /// grants rating points once per mini-phrase. Retried once on failure.
  void sendMiniPhraseAnswer(int miniPhraseId, List<String> answer, {int? lessonId}) {
    Future<void> send() async {
      final res = await http.post(
        _uri('/mini-phrases/$miniPhraseId/answer'),
        headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
        body: jsonEncode({'answer': answer, 'lesson_id': lessonId}),
      );
      if (res.statusCode >= 500) throw ApiException('retry');
    }

    unawaited(send().catchError((_) async {
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        await send();
      } catch (_) {
        // Lost: the next lesson pass shows this mini-phrase again anyway.
      }
    }));
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
    final json = categoryId == null && !uncategorized
        ? _remember('learned-words-$dictionaryId-$includeInProgress', res)
        : jsonDecode(utf8.decode(res.bodyBytes));
    return _parseWords(json);
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
    // Opening (or refreshing) the Уроки list is exactly when a pass played
    // offline should be handed over: whatever is still on the device goes first,
    // so the list that follows already reflects it on the server too.
    if (await PendingAnswers.hasWork()) unawaited(flushPendingAnswers());
    final res = await http.get(
      _uri('/dictionaries/$dictionaryId/lessons'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    final body = _remember('lessons-$dictionaryId', res) as Map<String, dynamic>;
    final list = body['lessons'] as List<dynamic>;
    return _withLocalProgress(list.map((e) => LessonSummary.fromJson(e as Map<String, dynamic>)).toList());
  }

  /// Lesson summaries with the passes this device played but the server has not
  /// confirmed yet folded in.
  ///
  /// A lesson finished with no network must not look unfinished the moment the
  /// user leaves it -- and its words must not look untouched -- just because the
  /// server has not heard about the pass yet. The local scores are exactly what
  /// the results screen showed, so the two agree; the server's own numbers
  /// replace them after the pass goes over (ApiClient.flushPendingAnswers).
  List<LessonSummary> _withLocalProgress(List<LessonSummary> lessons) {
    if (lessons.isEmpty) return lessons;
    final threshold = (cachedExerciseScoring() ?? ExerciseScoring.fallback).threshold;
    final result = <LessonSummary>[];
    for (final lesson in lessons) {
      final scores = LessonScoreOverlay.scoresFor(lesson.id);
      if (scores.isEmpty) {
        result.add(lesson);
        continue;
      }
      final total = lesson.wordCount == 0 ? scores.length : lesson.wordCount;
      final learned = scores.values.where((score) => score >= threshold).length;
      result.add(
        LessonSummary(
          id: lesson.id,
          number: lesson.number,
          isCompleted: lesson.isCompleted || (total > 0 && learned >= total),
          wordCount: lesson.wordCount,
          learnedCount: learned > total ? total : learned,
        ),
      );
    }
    return result;
  }

  Future<LessonCandidateWords> fetchLessonCandidateWords(int dictionaryId) async {
    final res = await http.get(
      _uri('/dictionaries/$dictionaryId/lesson-candidate-words'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    // Remembered on the device as well: "Создать урок" opens on the pool it
    // already has and refreshes quietly, instead of a loader.
    return LessonCandidateWords.fromJson(_remember('lesson-words-$dictionaryId', res) as Map<String, dynamic>);
  }

  /// The word pool «Создать урок» last saw, straight off the device -- no
  /// network and no waiting. Null until [prefetchLessonWords] (or a real
  /// fetch) has stored one for this dictionary.
  LessonCandidateWords? cachedLessonCandidateWords(int dictionaryId) =>
      _cached('lesson-words-$dictionaryId', (j) => LessonCandidateWords.fromJson(j as Map<String, dynamic>));

  /// Warms «Создать урок» in the background: the candidate words and their
  /// translations are fetched once and kept on the device, so opening the
  /// screen later needs no loading state at all. Called right after login and
  /// whenever the chosen dictionary changes.
  ///
  /// Silent and best-effort by design: it is an optimisation, never a step
  /// anybody waits on. Photos and audio are deliberately NOT prefetched --
  /// those are large and are still fetched the moment they are shown.
  Future<void> prefetchLessonWords(int dictionaryId) async {
    try {
      await fetchLessonCandidateWords(dictionaryId);
    } catch (_) {
      // Offline, or nothing to offer yet: the screen fetches for itself.
    }
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
    return _rememberLesson(res);
  }

  Future<Lesson> fetchLesson(int lessonId) async {
    final res = await http.get(_uri('/lessons/$lessonId'), headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    return _rememberLesson(res);
  }

  /// Parses a lesson and keeps the raw body on the device under its id.
  ///
  /// EVERY path that returns a lesson goes through here, because the lesson as
  /// it was BEFORE a pass is what the phone scores an offline pass against (see
  /// ApiClient.cachedLesson and services/lesson_scoring.dart). A single path
  /// that forgot to leave a copy was enough to break offline results entirely.
  Lesson _rememberLesson(http.Response res) {
    final body = utf8.decode(res.bodyBytes);
    final lesson = Lesson.fromJson(jsonDecode(body) as Map<String, dynamic>);
    DiskCache.put('lesson-${lesson.id}', body);
    // What the user is shown carries the passes this device already played
    // offline; the raw body above is the server's own copy, kept clean for
    // exactly that reason (see cachedLesson).
    return LessonScoreOverlay.applied(lesson, cachedExerciseScoring() ?? ExerciseScoring.fallback);
  }

  /// The device's copy of this lesson, without a request. Null until it has
  /// been fetched at least once (see [fetchLesson]).
  Lesson? cachedLesson(int lessonId) => _cached('lesson-$lessonId', (j) => Lesson.fromJson(j as Map<String, dynamic>));

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
    // Every answer of the pass must be on the server before it counts.
    await flushLessonAnswers();
    final res = await http
        .post(_uri('/lessons/$lessonId/pass/finish'), headers: await _authHeaders())
        .timeout(kOfflineActionTimeout);
    await _throwWithDetail(res);
    try {
      reportStreakResult(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
    } catch (_) {}
  }

  Future<Lesson> startLessonPass(int lessonId) async {
    final res = await http
        .post(_uri('/lessons/$lessonId/pass'), headers: await _authHeaders())
        .timeout(kOfflineActionTimeout);
    await _throwIfUnauthorized(res);
    // The pass's own starting point: exactly the "before" an offline pass is
    // scored against.
    return _rememberLesson(res);
  }

  /// Opens this pass on the server BEHIND the lesson that is already running
  /// (see LessonRunScreen): every word the pass covers is on the device, so the
  /// first exercise is playable at once and this goes on behind it. With no
  /// network, waiting for it in front of the lesson used to mean five seconds of
  /// breathing logo before the first card appeared.
  ///
  /// The order is what this method is for. An answer must never reach the server
  /// before the pass it belongs to, or the server records a score for a pass it
  /// has not opened (and drops it again the moment one is). So nothing this pass
  /// does goes out until [open] has concluded: an answer given meanwhile waits on
  /// the gate below, and if [open] fails the opening is written to the device's
  /// queue first, ahead of the answers waiting behind that gate.
  ///
  /// [open] is the request itself (LessonRunDriver.startPass), so the caller
  /// keeps owning how a pass is opened.
  Future<void> openLessonPass(int lessonId, Future<void> Function() open) async {
    // Two passes of one lesson at once would be a bug, and a gate left closed by
    // one of them must never hold the other's answers back forever.
    final stale = _passOpening;
    if (stale != null && !stale.isCompleted) stale.complete();
    final gate = _passOpening = Completer<void>();
    try {
      await open();
    } catch (_) {
      // No network: the opening waits on the device, in its own place ahead of
      // this pass's answers (see PendingAnswers.addStart).
      await PendingAnswers.addStart(lessonId);
    } finally {
      _passOpening = null;
      gate.complete();
    }
  }

  /// The pass being opened on the server right now, if any: answers written while
  /// it is closed wait behind it (see [openLessonPass]).
  Completer<void>? _passOpening;

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
    final lesson = _rememberLesson(res);
    // And the device's own LIST of this dictionary is refreshed while we are
    // online. That list is what «Уроки» shows when there is no network, and it
    // was written BEFORE this lesson existed -- so a lesson created here and then
    // played offline (or simply reopened offline) was missing from it: the screen
    // offered to create it again, and the server, which already had it, refused.
    try {
      await fetchLessons(lesson.dictionaryId);
    } catch (_) {
      // The list refreshes the next time «Уроки» is opened with a connection.
    }
    return lesson;
  }

  Future<TrueOrFalseRound> fetchLessonTrueOrFalseRound(int lessonId) async {
    final res = await http.get(
      _uri('/lessons/$lessonId/exercises/true-or-false'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    // Kept on the device as well: a prepared lesson reopens instantly (and
    // works with no network) instead of asking for the same round again.
    return TrueOrFalseRound.fromJson(_remember('lesson-round-$lessonId-true_or_false', res) as Map<String, dynamic>);
  }

  /// Same generic shape as [fetchExerciseLearnedWords], sourced from this
  /// lesson's fixed word set instead of the dictionary's learned words.
  Future<List<GuyoWord>> fetchLessonMatchingWords(int lessonId) async {
    final res = await http.get(
      _uri('/lessons/$lessonId/exercises/matching'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return _parseMatchingWords(_remember('lesson-round-$lessonId-matching', res));
  }

  Future<BuildWordRound> fetchLessonBuildWordRound(int lessonId) async {
    final res = await http.get(
      _uri('/lessons/$lessonId/exercises/build-word'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return BuildWordRound.fromJson(_remember('lesson-round-$lessonId-build_word', res) as Map<String, dynamic>);
  }

  Future<SpeakingWordRound> fetchLessonSpeakingWordRound(int lessonId) async {
    final res = await http.get(
      _uri('/lessons/$lessonId/exercises/speaking-word'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return SpeakingWordRound.fromJson(_remember('lesson-round-$lessonId-speaking_word', res) as Map<String, dynamic>);
  }

  Future<ListenWordRound> fetchLessonListenWordRound(int lessonId) async {
    final res = await http.get(
      _uri('/lessons/$lessonId/exercises/listen-word'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return ListenWordRound.fromJson(_remember('lesson-round-$lessonId-listen_word', res) as Map<String, dynamic>);
  }

  // --- Подготовка урока (офлайн) -------------------------------------------
  // What lesson preparation reads back off the device: the rounds of every
  // exercise and the scoring rules. Everything here was stored by an earlier
  // fetch, so it costs nothing and works with no network.

  /// The device's copy of one exercise's prepared round, or null.
  Object? cachedLessonRound(int lessonId, String exerciseKey) => switch (exerciseKey) {
        'true_or_false' => _cached(
            'lesson-round-$lessonId-true_or_false', (j) => TrueOrFalseRound.fromJson(j as Map<String, dynamic>)),
        'matching' => _cached('lesson-round-$lessonId-matching', _parseMatchingWords),
        'build_word' => _cached(
            'lesson-round-$lessonId-build_word', (j) => BuildWordRound.fromJson(j as Map<String, dynamic>)),
        'speaking_word' => _cached(
            'lesson-round-$lessonId-speaking_word', (j) => SpeakingWordRound.fromJson(j as Map<String, dynamic>)),
        'listen_word' => _cached(
            'lesson-round-$lessonId-listen_word', (j) => ListenWordRound.fromJson(j as Map<String, dynamic>)),
        _ => null,
      };

  /// Scoring rules for every exercise (GET /exercises/scoring) -- what the
  /// phone mirrors to score a lesson with no network. Stored on the device
  /// when a lesson is prepared; the server still recomputes everything.
  Future<ExerciseScoring> fetchExerciseScoring() async {
    final res = await http.get(_uri('/exercises/scoring'), headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    return ExerciseScoring.fromJson(_remember('exercise-scoring', res) as Map<String, dynamic>);
  }

  ExerciseScoring? cachedExerciseScoring() =>
      _cached('exercise-scoring', (j) => ExerciseScoring.fromJson(j as Map<String, dynamic>));

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

  final Set<Future<void>> _pendingLessonAnswers = {};

  /// Sends a lesson answer in the background: the exercise moves on at once
  /// (it already judged the answer itself) and the server gets it a moment
  /// later.
  ///
  /// The answer is written to the DEVICE first -- see [PendingAnswers] -- and
  /// only forgotten once the server has taken it. So a killed app, a dead
  /// network or a phone switched off mid-lesson never loses a pass's progress:
  /// [flushPendingAnswers] resends whatever is left. [flushLessonAnswers] waits
  /// for what is still on its way right now.
  void queueLessonAnswer(int lessonId, String exerciseKey, {required int wordId, required bool isCorrect}) {
    // Taken now, before the next question resets them.
    final signals = AnswerSignals.take();
    final answer = <String, dynamic>{
      'lesson_id': lessonId,
      'exercise_key': exerciseKey,
      'word_id': wordId,
      'is_correct': isCorrect,
      // When it was answered: the pass's own statistics (its duration) are
      // built from these, and a late arrival must not look instantaneous.
      'at': DateTime.now().millisecondsSinceEpoch,
      // Whether the server should hold this score until the pass is finished:
      // recorded per answer, because a resend after a restart has no way to
      // know how the lesson was being run.
      'deferred': deferredLessonId == lessonId,
      ...signals,
    };

    late final Future<void> job;
    job = _storeThenSend(answer).whenComplete(() => _pendingLessonAnswers.remove(job));
    _pendingLessonAnswers.add(job);
  }

  /// Writes the answer down, then tries to deliver it -- twice, a second
  /// apart. If it still will not go, it stays on the device for
  /// [flushPendingAnswers] rather than being silently dropped.
  Future<void> _storeThenSend(Map<String, dynamic> answer) async {
    // Nothing of a pass may reach the server before the pass itself: an answer
    // given while its pass was still opening waits here, and is written down
    // after that opening has concluded (see [openLessonPass]).
    await _passOpening?.future;
    final id = await PendingAnswers.add(answer);
    _answersInFlight.add(id);
    var delivered = false;
    try {
      try {
        await _postLessonAnswer(answer);
        delivered = true;
      } catch (_) {
        try {
          await Future<void>.delayed(const Duration(seconds: 1));
          await _postLessonAnswer(answer);
          delivered = true;
        } catch (_) {
          // Kept on the device; the next flush picks it up.
        }
      }
    } finally {
      _answersInFlight.remove(id);
    }
    if (delivered) await PendingAnswers.remove(id);
  }

  /// Entries whose request is in the air right now: the queue must leave them
  /// alone (see [_storeThenSend]). Without this the same answer reached the
  /// server twice -- two identical rows in its history, and, before the server's
  /// own guard, the word's score moved twice.
  final Set<int> _answersInFlight = {};

  Future<void> _postLessonAnswer(Map<String, dynamic> answer) async {
    final res = await http.post(
      _uri('/lessons/${answer['lesson_id']}/exercises/${answer['exercise_key']}/answers'),
      headers: await _authHeaders(),
      body: jsonEncode({
        for (final entry in answer.entries)
          // The moment the answer was really given. An answer made with no
          // network reaches the server much later, and the memory model reads
          // DAYS -- so this is what the server records as its time (clamped on
          // its side: never in the future, never before the pass began).
          if (entry.key == 'at')
            'answered_at_ms': entry.value
          else if (entry.key != 'id' &&
              entry.key != 'kind' &&
              entry.key != 'lesson_id' &&
              entry.key != 'exercise_key')
            entry.key: entry.value,
      }),
    );
    await _throwWithDetail(res);
  }

  /// One queued entry, in the order it happened: the pass opening, one answer,
  /// or the pass being played to the end.
  Future<void> _postAction(Map<String, dynamic> action) async {
    switch (action['kind'] ?? 'answer') {
      case 'start':
        await startLessonPass(action['lesson_id'] as int);
      case 'finish':
        await finishLessonPass(action['lesson_id'] as int);
      default:
        await _postLessonAnswer(action);
    }
  }

  /// Resends everything this device is still holding back, in order. Called once
  /// the user is logged in, whenever the app opens, and after a lesson's results:
  /// work done offline is worth exactly as much as work done on time.
  ///
  /// Stops at the first failure rather than skipping ahead -- the entries build
  /// on each other (a pass must be open before its answers, and the answers'
  /// order is the pass's own order).
  Future<void> flushPendingAnswers() async {
    await PendingAnswers.load();
    // The lessons whose work is going over now: once the server has taken it,
    // its own numbers for them are the true ones, so anything this device
    // scored for itself is dropped and the fresh copies are fetched.
    final touched = <int>{
      for (final action in PendingAnswers.all)
        if (action['lesson_id'] is int) action['lesson_id'] as int,
    };
    // Whatever happens below, the retry loop runs from here on: this is the one
    // place that knows the device has something to hand over, so nothing has to
    // remember to start it at app launch (and nothing did -- see startPendingFlush).
    _ensurePendingFlush();
    for (final action in PendingAnswers.all) {
      final id = action['id'];
      if (id is! int) continue;
      // Already on its way: sending it from here as well is exactly how the same
      // answer used to reach the server twice (see _storeThenSend).
      if (_answersInFlight.contains(id)) continue;
      try {
        await _postAction(action);
      } on ApiException catch (e) {
        // The server REFUSED this one (404 "этого слова нет в уроке", 409, 422 --
        // a pass whose word set the server worked out differently than the round
        // prepared on the device). Retrying it forever is what froze the whole
        // queue: every flush died on this one entry, so no answer after it ever
        // reached the server and the lesson stayed at "Изучено 0 из 4" -- the
        // pass played on the phone, counted by nobody.
        final code = e.statusCode;
        if (code == null || code < 400 || code >= 500) rethrow;
        debugPrint('[guyo] queue: dropping entry ${action['kind']} for lesson '
            '${action['lesson_id']} -- server said $code: ${e.message}');
        await PendingAnswers.remove(id);
        continue;
      } catch (_) {
        return; // No network (or the server is down): it stays, for the next attempt.
      }
      await PendingAnswers.remove(id);
    }
    if (touched.isEmpty) return;
    // Everything went over: the screens that were waiting for exactly this are
    // told, so the lesson's state changes on its own (see syncTick).
    syncTick.value++;
    for (final lessonId in touched) {
      // Only once NOTHING is left for this lesson. The queue's LAST entry is the
      // pass's own finish, and the server only counts the pass when that lands --
      // so forgetting the device's own result here (and fetching the server's
      // still-unfinished copy) is exactly what flashed "0% / пройдите заново"
      // right after a sync, before the finish arrived. Until the finish is gone,
      // the local result stands and the card keeps saying it is syncing.
      if (PendingAnswers.forLesson(lessonId).isNotEmpty) continue;
      LessonScoreOverlay.forget(lessonId);
      unawaited(() async {
        try {
          await fetchLesson(lessonId);
        } catch (_) {
          // The device's copy refreshes the next time the lesson is opened.
        }
      }());
    }
  }

  /// Ticks every time the device's own lesson work actually goes over to the
  /// server. Screens that show a lesson's state listen to it, so «Синхронизируется
  /// с сервером…» turns into the confirmed result by itself -- no reload, no
  /// reopening the app: the whole point is that the user never has to do anything
  /// for the truth to arrive.
  final ValueNotifier<int> syncTick = ValueNotifier<int>(0);

  /// Retries the device's pending lesson work every few seconds while the app is
  /// running.
  ///
  /// A pass played with no network has to reach the server as soon as there IS
  /// one: without this, the work would sit on the phone until the app was
  /// reopened, and the lesson would look unplayed (and its words untouched) in
  /// the meantime.
  ///
  /// FIVE seconds, and it starts ITSELF the first time anything is queued (see
  /// [_ensurePendingFlush]) -- it used to be thirty and, worse, nothing ever called
  /// it, so a finished pass could sit on the device indefinitely: the user waited
  /// for a sync that was never scheduled.
  void startPendingFlush({Duration every = const Duration(seconds: 5)}) {
    if (_pendingFlushTimer != null) return;
    _pendingFlushTimer = Timer.periodic(every, (_) async {
      if (await PendingAnswers.hasWork()) await flushPendingAnswers();
    });
  }

  /// Starts the retry loop if it is not running: called from the one place that
  /// knows there is something to hand over.
  void _ensurePendingFlush() => startPendingFlush();

  Timer? _pendingFlushTimer;

  /// Waits for the answers that are on their way right now (they are sent in the
  /// background so an exercise never waits on the network). Called before a pass
  /// is finished, so the server has every one of them.
  Future<void> flushLessonAnswers() => Future.wait(List<Future<void>>.of(_pendingLessonAnswers));

  // --- Профиль и Достижения ------------------------------------------------
  // Avatar storage and achievement earning/eligibility are entirely
  // backend-decided (see backend/app/achievements/) -- this client only
  // fetches/uploads and renders the result.

  Future<UserProfile> fetchMyProfile() async {
    final res = await http.get(_uri('/users/me/profile'), headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    final profile = UserProfile.fromJson(_remember('profile', res) as Map<String, dynamic>);
    setStreakState(litToday: profile.streakActiveToday, days: profile.currentStreakDays);
    return profile;
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

  /// Live sign-up check: false when the login is already taken (the rules
  /// themselves are checked on the device, see login_rules.dart). Null
  /// when the server can't be reached -- the caller decides.
  Future<bool?> isLoginAvailable(String login) async {
    try {
      final res = await http.get(
        _uri('/auth/login-available?login=${Uri.encodeQueryComponent(login)}'),
        headers: {'X-App-Build': '$appBuild'},
      );
      if (res.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return data['available'] as bool;
    } catch (_) {
      return null;
    }
  }

  /// The times of day the user picked to study (reminders go out at each).
  Future<List<StudyTime>> fetchStudyTimes() async {
    final res = await http.get(_uri('/notifications/study-times'), headers: await _authHeaders());
    await _throwWithDetail(res);
    return _parseStudyTimes(_remember('study-times', res));
  }

  /// Replaces the whole list; returns what the server stored.
  Future<List<StudyTime>> saveStudyTimes(List<StudyTime> times) async {
    final res = await http.put(
      _uri('/notifications/study-times'),
      headers: await _authHeaders(),
      body: jsonEncode({'times': [for (final t in times) t.toJson()]}),
    );
    await _throwWithDetail(res);
    return _parseStudyTimes(_remember('study-times', res));
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
    final list = _remember('achievements', res) as List<dynamic>;
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
    return UserRating.fromJson(_remember('rating', res) as Map<String, dynamic>);
  }

  /// Top 100 users sharing the CALLER's own current rank -- the backend
  /// decides which rank that is; there is no way to ask for a different
  /// one.
  Future<Leaderboard> fetchMyRankLeaderboard() async {
    final res = await http.get(_uri('/rating/leaderboard'), headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    return Leaderboard.fromJson(_remember('leaderboard', res) as Map<String, dynamic>);
  }

  /// The word-reinforcement ladder, enabled levels only, lowest
  /// score-range first -- see WordLevelSummary's own doc.
  Future<List<WordLevelSummary>> fetchWordLevels() async {
    final res = await http.get(_uri('/word-levels'), headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    return _parseWordLevels(_remember('word-levels', res));
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
  /// The caller and their friends, by points (GET /rating/leaderboard/friends).
  Future<Leaderboard> fetchFriendsLeaderboard() async {
    final res = await http.get(_uri('/rating/leaderboard/friends'), headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    return Leaderboard.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// Who a 9-digit ID belongs to (GET /rating/users/{id}) -- shown before
  /// adding a friend.
  Future<FoundUser> findUserByPublicId(int publicId) async {
    final res = await http.get(_uri('/rating/users/$publicId'), headers: await _authHeaders());
    await _throwWithDetail(res);
    return FoundUser.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// Adds the account with this 9-digit ID as a friend (both ways).
  Future<void> addFriend(int publicId) async {
    final res = await http.post(
      _uri('/rating/friends'),
      headers: await _authHeaders(),
      body: jsonEncode({'public_id': publicId}),
    );
    await _throwWithDetail(res);
  }

  Future<void> removeFriend(int userId) async {
    final res = await http.delete(_uri('/rating/friends/$userId'), headers: await _authHeaders());
    await _throwWithDetail(res);
  }

  /// Marks a phrase as actually OPENED (the "phrases_opened" achievement
  /// counts these). Fire-and-forget: opening a phrase must never block or
  /// break the UI, and the server records it only once per phrase, so a
  /// failed or repeated call is harmless.
  Future<void> openPhrase(int dictionaryId, int phraseId) async {
    try {
      await http.post(
        _uri('/dictionaries/$dictionaryId/phrases/$phraseId/open'),
        headers: await _authHeaders(),
      );
    } catch (_) {
      // Ignored on purpose -- a missed open just isn't counted.
    }
  }

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
    return _parseRanks(_remember('ranks', res));
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
    return SeasonQuestOverview.fromJson(_remember('overview-$dictionaryId', res) as Map<String, dynamic>);
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
    return _parseStreak(_remember('streak', res));
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
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    reportStreakResult(json);
    return QuestAnswerResult.fromJson(json);
  }

  // --- Проверка текста -----------------------------------------------------
  // One AI call per message. The backend does the whole check (DeepSeek) and
  // returns the mistakes, the summary and the corrected text; nothing here is
  // stored, scored or remembered -- this is a writing aid, not an exercise.

  /// GET /text-check/info: whether the checker is on, how long a message may
  /// be, and how many checks are left today -- everything the screen needs
  /// BEFORE the first message is typed.
  Future<TextCheckInfo> fetchTextCheckInfo() async {
    final res = await http.get(_uri('/text-check/info'), headers: await _authHeaders());
    await _throwWithDetail(res);
    return TextCheckInfo.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// POST /text-check: checks one Russian message the user is about to send.
  ///
  /// [formality] is either "formal" or null: null means "do not check
  /// formality at all", which is what the app's 🎩 switch off means.
  Future<TextCheckResult> checkText({
    required String text,
    required String userGender,
    required String addresseeGender,
    String? formality,
    required bool checkPunctuation,
    required String explanationLanguage,
  }) async {
    final res = await http.post(
      _uri('/text-check'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'text': text,
        'user_gender': userGender,
        'addressee_gender': addresseeGender,
        if (formality != null && formality.isNotEmpty) 'formality': formality,
        'check_punctuation': checkPunctuation,
        'explanation_language': explanationLanguage,
      }),
    );
    await _throwWithDetail(res);
    return TextCheckResult.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }
}
