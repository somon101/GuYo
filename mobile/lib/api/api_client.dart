import '../services/streak_state.dart';

import 'dart:async';

import '../services/google_auth.dart';
import '../services/disk_cache.dart';
import '../widgets/study_times_editor.dart' show StudyTime;
import '../widgets/update_required.dart';
import '../screens/stats_screen.dart' show UserStats;
import '../services/session_cache.dart';
import '../widgets/session_expired.dart';
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
import '../models/language.dart';
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
import '../models/word_check.dart';
import '../models/season_pass.dart';
import '../models/season_summary.dart';
import '../models/chest.dart';
import '../services/chest_queue.dart';
import '../models/daily_goal.dart';
import '../models/duel.dart';
import '../models/my_progress.dart';
import '../models/team.dart';
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

  /// Streak freezes in stock: spent by themselves when a gap would break the streak.
  final int freezes;
  final int mergedDays;
  final int mergeItems;
  const StreakInfo({
    required this.currentStreakDays,
    required this.today,
    required this.activeDates,
    this.frozenDates = const [],
    this.freezes = 0,
    this.mergedDays = 0,
    this.mergeItems = 0,
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
  final ValueNotifier<int?> economyBalance = ValueNotifier<int?>(null);

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
    _cachedToken = null;
    // Whatever was kept belongs to the account that just left.
    SessionCache.clear();
    await DiskCache.clear();
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
      throw ApiException(
        tr('Ошибка сервера ({0})', [res.statusCode]),
        statusCode: res.statusCode,
      );
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
        if (profile.uiLanguage != appLanguage.value)
          await setAppLanguage(profile.uiLanguage);
      }
    } catch (_) {}
  }

  /// One step of the learner's history (backend app/analytics/history.py):
  /// app_opened, lesson_opened/left, quest_opened/left. Fire-and-forget --
  /// a lost event must never disturb learning.
  void logEvent(
    String kind, {
    int? lessonId,
    int? questId,
    Map<String, Object>? data,
  }) {
    () async {
      try {
        await http.post(
          _uri('/events'),
          headers: {
            ...await _authHeaders(),
            'Content-Type': 'application/json',
          },
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
      final detail = (jsonDecode(
        utf8.decode(res.bodyBytes),
      ) as Map<String, dynamic>)['detail'];
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
      throw ApiException(
        _detailOf(res, tr('Ошибка сервера ({0})', [res.statusCode])),
        statusCode: res.statusCode,
      );
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
      throw ApiException(
        _detailOf(res, tr('Ошибка сервера ({0})', [res.statusCode])),
        statusCode: res.statusCode,
      );
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    await _saveToken(data['access_token'] as String);
  }

  /// A Практика round played to the end: lights today's streak day
  /// (backend POST .../practice/finish). Fire-and-forget.
  void finishPractice(int dictionaryId) {
    () async {
      try {
        final res = await http.post(
          _uri('/dictionaries/$dictionaryId/practice/finish'),
          headers: await _authHeaders(),
        );
        if (res.statusCode == 200)
          reportStreakResult(
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
          );
      } catch (_) {}
    }();
  }

  /// Ends every other sign-in of this account; this device gets a fresh token.
  Future<void> logoutEverywhere() async {
    final res = await http.post(
      _uri('/auth/logout-all'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    await _saveToken(data['access_token'] as String);
  }

  Future<void> logout() async {
    SessionCache.clear();
    await DiskCache.clear();
    await clearToken();
  }

  /// Удаляет аккаунт (требование Google Play). Строка на сервере помечается
  /// удалённой и исчезает отовсюду; вернуть её можно, войдя тем же логином и
  /// паролем в течение 30 дней. После вызова локальные данные стираются, так
  /// что вызывающий должен увести человека на экран входа.
  Future<void> deleteMyAccount() async {
    final res = await http.delete(
      _uri('/users/me'),
      headers: await _authHeaders(),
    );
    await _throwWithDetail(res);
  }

  /// The published-language list for the sign-up wizard's first step --
  /// reachable with no token at all (there is no account yet), unlike
  /// [fetchDictionaries] below which this deliberately does not touch or
  /// duplicate the logic of otherwise (same published-only list, just a
  /// route that doesn't require being logged in already -- see backend
  /// GET /dictionaries/public).
  Future<List<GuyoDictionary>> fetchPublicDictionaries() async {
    final res = await http.get(
      _uri('/dictionaries/public'),
      headers: {'Content-Type': 'application/json'},
    );
    await _throwIfUnauthorized(res);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list
        .map((e) => GuyoDictionary.fromJson(e as Map<String, dynamic>))
        .toList();
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

  /// Языки, доступные для изучения. Список живёт в базе и правится в админке,
  /// поэтому в приложении он не зашит: добавили язык — он появился здесь.
  Future<List<GuyoLanguage>> fetchLanguages() async {
    final res = await http.get(
      _uri('/languages'),
      headers: await _authHeaders(),
    );
    await _throwWithDetail(res);
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return data
        .map((e) => GuyoLanguage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<GuyoDictionary>> fetchDictionaries() async {
    final res = await http.get(
      _uri('/dictionaries'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return _parseDictionaries(_remember('dictionaries', res));
  }

  List<GuyoDictionary> _parseDictionaries(dynamic json) =>
      (json as List<dynamic>)
          .map((e) => GuyoDictionary.fromJson(e as Map<String, dynamic>))
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

  List<GuyoDictionary>? cachedDictionaries() =>
      _cached('dictionaries', _parseDictionaries);
  SeasonQuestOverview? cachedSeasonQuestOverview(int dictionaryId) => _cached(
    'overview-$dictionaryId',
    (j) => SeasonQuestOverview.fromJson(j as Map<String, dynamic>),
  );
  UserProfile? cachedMyProfile() => _cached(
    'profile',
    (j) => UserProfile.fromJson(j as Map<String, dynamic>),
  );
  List<UserAchievement>? cachedMyAchievements() => _cached(
    'achievements',
    (j) => (j as List<dynamic>)
        .map((e) => UserAchievement.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
  UserRating? cachedMyRating() =>
      _cached('rating', (j) => UserRating.fromJson(j as Map<String, dynamic>));
  List<LessonSummary>? cachedLessons(int dictionaryId) => _cached(
    'lessons-$dictionaryId',
    (j) => ((j as Map<String, dynamic>)['lessons'] as List<dynamic>)
        .map((e) => LessonSummary.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
  Leaderboard? cachedMyRankLeaderboard() => _cached(
    'leaderboard',
    (j) => Leaderboard.fromJson(j as Map<String, dynamic>),
  );
  List<GuyoWord>? cachedLearnedWords(
    int dictionaryId, {
    bool includeInProgress = false,
  }) => _cached('learned-words-$dictionaryId-$includeInProgress', _parseWords);
  List<LearnedCategory>? cachedLearnedCategories(
    int dictionaryId, {
    bool includeInProgress = false,
  }) => _cached(
    'learned-categories-$dictionaryId-$includeInProgress',
    _parseLearnedCategories,
  );
  List<WordLevelSummary>? cachedWordLevels() =>
      _cached('word-levels', _parseWordLevels);
  List<RankSummary>? cachedAllRanks() => _cached('ranks', _parseRanks);
  StreakInfo? cachedMyStreak() => _cached('streak', _parseStreak);
  List<StudyTime>? cachedStudyTimes() =>
      _cached('study-times', _parseStudyTimes);

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

  List<GuyoWord> _parseWords(dynamic json) => (json as List<dynamic>)
      .map((e) => GuyoWord.fromJson(e as Map<String, dynamic>))
      .toList();
  List<LearnedCategory> _parseLearnedCategories(dynamic json) =>
      (json as List<dynamic>)
          .map((e) => LearnedCategory.fromJson(e as Map<String, dynamic>))
          .toList();
  List<WordLevelSummary> _parseWordLevels(dynamic json) =>
      (json as List<dynamic>)
          .map((e) => WordLevelSummary.fromJson(e as Map<String, dynamic>))
          .toList();
  List<RankSummary> _parseRanks(dynamic json) => (json as List<dynamic>)
      .map((e) => RankSummary.fromJson(e as Map<String, dynamic>))
      .toList();

  StreakInfo _parseStreak(dynamic json) {
    final map = json as Map<String, dynamic>;
    DateTime day(String s) {
      final d = DateTime.parse(s);
      return DateTime(d.year, d.month, d.day);
    }

    return StreakInfo(
      currentStreakDays: map['current_streak_days'] as int,
      today: day(map['today'] as String),
      activeDates: [
        for (final s in map['active_dates'] as List<dynamic>) day(s as String),
      ],
      frozenDates: [
        for (final s in (map['frozen_dates'] as List<dynamic>? ?? const []))
          day(s as String),
      ],
      freezes: (map['freezes'] as int?) ?? 0,
      mergedDays: (map['merged_days'] as int?) ?? 0,
      mergeItems: (map['streak_merge_items'] as int?) ?? 0,
    );
  }

  Future<Map<String, dynamic>> fetchEconomy() async {
    final res = await http.get(_uri('/shop'), headers: await _authHeaders());
    await _throwWithDetail(res);
    final data = _remember('shop', res) as Map<String, dynamic>;
    economyBalance.value = data['diamonds'] as int?;
    return data;
  }

  /// The last shop answer (balance, products), for an instant first frame.
  Map<String, dynamic>? cachedEconomy() =>
      _cached('shop', (j) => j as Map<String, dynamic>);
  DailyGoal? cachedDailyGoal() => _cached(
    'daily-goal',
    (j) => DailyGoal.fromJson(j as Map<String, dynamic>),
  );
  DuelState? cachedDuels() =>
      _cached('duels', (j) => DuelState.fromJson(j as Map<String, dynamic>));
  SeasonPass? cachedSeasonPass() {
    final body = DiskCache.get('season-pass');
    if (body == null || body == 'null') return null;
    try {
      return SeasonPass.fromJson(jsonDecode(body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> buyShopProduct(int id) async {
    final res = await http.post(
      _uri('/shop/$id/buy'),
      headers: await _authHeaders(),
    );
    await _throwWithDetail(res);
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    economyBalance.value = data['diamonds'] as int?;
    return data;
  }

  Future<Map<String, dynamic>> openGift(int id) async {
    final res = await http.post(
      _uri('/gifts/$id/open'),
      headers: await _authHeaders(),
    );
    await _throwWithDetail(res);
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    economyBalance.value = data['diamonds'] as int?;
    return data;
  }

  Future<Map<String, dynamic>> useStreakMerge() async {
    final res = await http.post(
      _uri('/shop/use/streak-merge'),
      headers: await _authHeaders(),
    );
    await _throwWithDetail(res);
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchStreakHistory(DateTime month) async {
    final query =
        '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';
    final res = await http.get(
      _uri('/users/me/streak/history')
          .replace(queryParameters: {'month': query}),
      headers: await _authHeaders(),
    );
    await _throwWithDetail(res);
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  Future<List<GuyoWord>> fetchWords(int dictionaryId) async {
    final res = await http.get(
      _uri('/dictionaries/$dictionaryId/words'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list
        .map((e) => GuyoWord.fromJson(e as Map<String, dynamic>))
        .toList();
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
      sessionExpired();
      throw ApiException(
        tr('Сессия истекла, войдите снова'),
        statusCode: res.statusCode,
      );
    }
    if (res.statusCode == 403) {
      throw ApiException(
        tr('Сессия истекла, войдите снова'),
        statusCode: res.statusCode,
      );
    }
    if (res.statusCode >= 400) {
      throw ApiException(
        tr('Ошибка сервера ({0})', [res.statusCode]),
        statusCode: res.statusCode,
      );
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
      sessionExpired();
      throw ApiException(
        tr('Сессия истекла, войдите снова'),
        statusCode: res.statusCode,
      );
    }
    if (res.statusCode == 403) {
      throw ApiException(
        tr('Сессия истекла, войдите снова'),
        statusCode: res.statusCode,
      );
    }
    if (res.statusCode >= 400) {
      String message = tr('Ошибка сервера ({0})', [res.statusCode]);
      try {
        final body =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
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
    return LearningSession.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<LearningSession> createLearningSession(
    int dictionaryId,
    int count,
  ) async {
    final res = await http.post(
      _uri('/learning/sessions'),
      headers: await _authHeaders(),
      body: jsonEncode({'dictionary_id': dictionaryId, 'count': count}),
    );
    await _throwWithDetail(res);
    return LearningSession.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<LearningSession> markWordLearned(int sessionId, int wordId) async {
    final res = await http.post(
      _uri('/learning/sessions/$sessionId/words/$wordId/learned'),
      headers: await _authHeaders(),
    );
    await _throwWithDetail(res);
    return LearningSession.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<LearningSession> markWordForReview(int sessionId, int wordId) async {
    final res = await http.post(
      _uri('/learning/sessions/$sessionId/words/$wordId/review'),
      headers: await _authHeaders(),
    );
    await _throwWithDetail(res);
    return LearningSession.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
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
    final uri = _uri('/learned-words/categories')
        .replace(queryParameters: params);
    final res = await http.get(uri, headers: await _authHeaders());
    await _throwIfUnauthorized(res);
    return _parseLearnedCategories(
      _remember('learned-categories-$dictionaryId-$includeInProgress', res),
    );
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
    return list
        .map((e) => GuyoPhrase.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Практика: mini-phrases this user has already gone through in a lesson.
  Future<List<MiniPhrase>> fetchOpenMiniPhrases(int dictionaryId) async {
    final res = await http.get(
      _uri('/dictionaries/$dictionaryId/mini-phrases/open'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    if (res.statusCode != 200)
      throw ApiException(tr('Не удалось загрузить мини-фразы'));
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list
        .map((e) => MiniPhrase.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// A "Собери фразу" answer for a mini-phrase. The app already judged it
  /// locally (the right answer is known), so this goes out in the
  /// background and never makes anyone wait; the server re-checks it and
  /// grants rating points once per mini-phrase. Retried once on failure.
  void sendMiniPhraseAnswer(
    int miniPhraseId,
    List<String> answer, {
    int? lessonId,
  }) {
    Future<void> send() async {
      final res = await http.post(
        _uri('/mini-phrases/$miniPhraseId/answer'),
        headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
        body: jsonEncode({'answer': answer, 'lesson_id': lessonId}),
      );
      if (res.statusCode >= 500) throw ApiException('retry');
    }

    unawaited(
      send().catchError((_) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        try {
          await send();
        } catch (_) {
          // Lost: the next lesson pass shows this mini-phrase again anyway.
        }
      }),
    );
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
    return TrueOrFalseRound.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  /// The generic "N random already-learned words" round, capped by
  /// [exerciseKey]'s admin-configured count on the backend. Used by
  /// "Сопоставление" (exerciseKey "matching") in place of the old
  /// fetchWords(dictionaryId) call -- everything downstream of the word
  /// list (shuffling into two columns, tap-to-match) is unchanged.
  Future<List<GuyoWord>> fetchExerciseLearnedWords(
    int dictionaryId,
    String exerciseKey,
  ) async {
    final res = await http.get(
      _uri('/dictionaries/$dictionaryId/exercises/$exerciseKey/learned-words'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final list = body['words'] as List<dynamic>;
    return list
        .map((e) => GuyoWord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<BuildWordRound> fetchBuildWordRound(int dictionaryId) async {
    final res = await http.get(
      _uri('/dictionaries/$dictionaryId/exercises/build-word'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return BuildWordRound.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
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
    final body =
        _remember('lessons-$dictionaryId', res) as Map<String, dynamic>;
    final list = body['lessons'] as List<dynamic>;
    return list
        .map((e) => LessonSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<LessonCandidateWords> fetchLessonCandidateWords(
    int dictionaryId,
  ) async {
    final res = await http.get(
      _uri('/dictionaries/$dictionaryId/lesson-candidate-words'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return LessonCandidateWords.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  /// Returns the current active (not-yet-completed) lesson for this
  /// dictionary, or null if there isn't one -- distinct from an error, same
  /// convention as [fetchActiveLearningSession].
  Future<Lesson?> fetchActiveLesson(int dictionaryId) async {
    final res = await http.get(
      _uri('/lessons/active')
          .replace(queryParameters: {'dictionary_id': '$dictionaryId'}),
      headers: await _authHeaders(),
    );
    if (res.statusCode == 404) return null;
    await _throwIfUnauthorized(res);
    return Lesson.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<Lesson> fetchLesson(int lessonId) async {
    final res = await http.get(
      _uri('/lessons/$lessonId'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return Lesson.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  /// Statistics of the pass that just finished (answers, accuracy, per
  /// exercise, per-word score gain).
  Future<LessonPassStats> fetchLessonPassStats(int lessonId) async {
    final res = await http.get(
      _uri('/lessons/$lessonId/pass/stats'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    if (res.statusCode != 200)
      throw ApiException(
        tr('Статистика недоступна'),
        statusCode: res.statusCode,
      );
    return LessonPassStats.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
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
  /// Makes the pass count, and returns the lesson as it now is together with
  /// the pass's statistics -- everything the results screen needs, in this one
  /// response (stats are null on a server that does not send them yet).
  Future<(Lesson, LessonPassStats?)> finishLessonPass(int lessonId) async {
    // Every answer of the pass must be on the server before it counts.
    await flushLessonAnswers();
    final res = await http.post(
      _uri('/lessons/$lessonId/pass/finish'),
      headers: await _authHeaders(),
    );
    await _throwWithDetail(res);
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    try {
      reportStreakResult(body);
    } catch (_) {}
    final stats = body['pass_stats'];
    return (
      Lesson.fromJson(body),
      stats is Map<String, dynamic> ? LessonPassStats.fromJson(stats) : null,
    );
  }

  /// Today's progress towards the daily goal; null on any failure.
  Future<DailyGoal?> fetchDailyGoal() async {
    try {
      final res = await http.get(
        _uri('/daily-goal'),
        headers: await _authHeaders(),
      );
      if (res.statusCode >= 400) return null;
      return DailyGoal.fromJson(_remember('daily-goal', res) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<DailyGoal?> setDailyGoal(int goal) async {
    try {
      final res = await http.put(
        _uri('/daily-goal'),
        headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
        body: jsonEncode({'goal': goal}),
      );
      if (res.statusCode >= 400) return null;
      return DailyGoal.fromJson(
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  /// The chest bank and the chest of the day; null on any failure. Remembered
  /// on disk so the card shows at once.
  Future<ChestBank?> fetchChests() async {
    try {
      final res = await http.get(_uri('/chests'), headers: await _authHeaders());
      if (res.statusCode >= 400) return null;
      _remember('chests', res);
      return ChestBank.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>).without(ChestQueue.pending);
    } catch (_) {
      return null;
    }
  }

  ChestBank? cachedChests() {
    final raw = DiskCache.get('chests');
    if (raw == null) return null;
    try {
      return ChestBank.fromJson(jsonDecode(raw) as Map<String, dynamic>).without(ChestQueue.pending);
    } catch (_) {
      return null;
    }
  }

  /// Tells the server these chests were opened on the phone (idempotent). Throws when it cannot.
  Future<void> sendOpenedChests(List<int> ids) async {
    final res = await http.post(
      _uri('/chests/open-ids'),
      headers: await _authHeaders(),
      body: jsonEncode({'ids': ids}),
    );
    await _throwWithDetail(res);
    _remember('chests', res.statusCode == 200 ? _stateOnly(res) : res);
  }

  http.Response _stateOnly(http.Response res) {
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return http.Response(jsonEncode(json['state']), 200, headers: res.headers);
  }

  /// Takes the chest of the day into the bank.
  Future<ChestBank> claimDailyChest() async {
    final res = await http.post(_uri('/chests/daily/claim'), headers: await _authHeaders());
    await _throwWithDetail(res);
    _remember('chests', res);
    return ChestBank.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// Opens 1, 5 or 10 chests of one kind at once; returns every prize and the refreshed bank.
  Future<(List<ChestPrize>, ChestBank)> openManyChests(String chestKey, int count) async {
    final res = await http.post(
      _uri('/chests/open-many'),
      headers: await _authHeaders(),
      body: jsonEncode({'chest_key': chestKey, 'count': count}),
    );
    await _throwWithDetail(res);
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final bank = ChestBank.fromJson(json['state'] as Map<String, dynamic>);
    DiskCache.put('chests', jsonEncode(json['state']));
    return (
      [
        for (final p in json['prizes'] as List<dynamic>)
          ChestPrize(chestKey: chestKey, kind: p['kind'] as String, amount: p['amount'] as int),
      ],
      bank,
    );
  }

  /// Opens one chest; returns the prize and the refreshed bank.
  Future<(ChestPrize, ChestBank)> openChest(int id) async {
    final res = await http.post(_uri('/chests/$id/open'), headers: await _authHeaders());
    await _throwWithDetail(res);
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final bank = ChestBank.fromJson(json['state'] as Map<String, dynamic>);
    DiskCache.put('chests', jsonEncode(json['state']));
    return (
      ChestPrize(chestKey: json['chest_key'] as String, kind: json['kind'] as String, amount: json['amount'] as int),
      bank,
    );
  }

  /// This week's duel and the recent ones; null on any failure.
  Future<DuelState?> fetchDuels() async {
    try {
      final res = await http.get(_uri('/duels'), headers: await _authHeaders());
      if (res.statusCode >= 400) return null;
      return DuelState.fromJson(_remember('duels', res) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<DuelState> challengeFriend(int friendId) async {
    final res = await http.post(
      _uri('/duels'),
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({'friend_id': friendId}),
    );
    await _throwWithDetail(res);
    return DuelState.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<DuelState> answerDuel(int id, {required bool accept}) async {
    final res = await http.post(
      _uri('/duels/$id/${accept ? 'accept' : 'decline'}'),
      headers: await _authHeaders(),
    );
    await _throwWithDetail(res);
    return DuelState.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  /// «Мой путь»: words learned per week; null on any failure.
  Future<MyProgress?> fetchMyProgress() async {
    try {
      final res = await http.get(
        _uri('/users/me/progress'),
        headers: await _authHeaders(),
      );
      if (res.statusCode >= 400) return null;
      return MyProgress.fromJson(
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  /// The recap of the last finished season; null if there is none (or on failure).
  Future<SeasonSummary?> fetchSeasonSummary() async {
    try {
      final res = await http.get(
        _uri('/season-pass/summary'),
        headers: await _authHeaders(),
      );
      if (res.statusCode >= 400) return null;
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      return body is Map<String, dynamic> ? SeasonSummary.fromJson(body) : null;
    } catch (_) {
      return null;
    }
  }

  /// The season pass; null while no season is live (or on any failure).
  Future<SeasonPass?> fetchSeasonPass() async {
    try {
      final res = await http.get(
        _uri('/season-pass'),
        headers: await _authHeaders(),
      );
      // No live season (404) must not leave an old pass on screen.
      if (res.statusCode == 404) {
        DiskCache.put('season-pass', 'null');
        return null;
      }
      if (res.statusCode >= 400) return null;
      return SeasonPass.fromJson(_remember('season-pass', res) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  // --- Teams ---------------------------------------------------------------

  Future<TeamState> _teamCall(
    Future<http.Response> Function(Map<String, String> h) send,
  ) async {
    final res = await send(await _authHeaders());
    await _throwWithDetail(res);
    return TeamState.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  /// This person's team (null inside), their invitations and the team size cap;
  /// null on any failure.
  Future<TeamState?> fetchMyTeam() async {
    try {
      final res = await http.get(
        _uri('/teams/me'),
        headers: await _authHeaders(),
      );
      if (res.statusCode >= 400) return null;
      return TeamState.fromJson(
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<OpenTeam>> fetchOpenTeams() async {
    final res = await http.get(
      _uri('/teams/open'),
      headers: await _authHeaders(),
    );
    await _throwWithDetail(res);
    return (jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>)
        .map((e) => OpenTeam.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TeamState> createTeam(String name, {required bool isOpen}) =>
      _teamCall(
        (h) => http.post(
          _uri('/teams'),
          headers: h,
          body: jsonEncode({'name': name, 'is_open': isOpen}),
        ),
      );

  Future<TeamState> updateTeam({String? name, bool? isOpen}) => _teamCall(
    (h) => http.put(
      _uri('/teams/me'),
      headers: h,
      body: jsonEncode({'name': name, 'is_open': isOpen}),
    ),
  );

  Future<TeamState> inviteToTeam(int userId) => _teamCall(
    (h) => http.post(
      _uri('/teams/me/invite'),
      headers: h,
      body: jsonEncode({'user_id': userId}),
    ),
  );

  Future<TeamState> acceptTeamInvite(int teamId) => _teamCall(
    (h) => http.post(_uri('/teams/invites/$teamId/accept'), headers: h),
  );

  Future<TeamState> declineTeamInvite(int teamId) => _teamCall(
    (h) => http.post(_uri('/teams/invites/$teamId/decline'), headers: h),
  );

  Future<TeamState> joinTeam(int teamId) =>
      _teamCall((h) => http.post(_uri('/teams/$teamId/join'), headers: h));

  Future<TeamState> leaveTeam() =>
      _teamCall((h) => http.post(_uri('/teams/me/leave'), headers: h));

  Future<TeamState> kickTeamMember(int userId) => _teamCall(
    (h) => http.delete(_uri('/teams/me/members/$userId'), headers: h),
  );

  /// Takes this person's share of a finished team goal: the bonus XP, the
  /// goal's reward (if any) and the refreshed team.
  Future<({TeamState state, int xp})> claimTeamGoal(
    String scope,
    String goalId,
  ) async {
    final res = await http.post(
      _uri('/teams/goals/claim'),
      headers: await _authHeaders(),
      body: jsonEncode({'scope': scope, 'goal_id': goalId}),
    );
    await _throwWithDetail(res);
    final map = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return (
      state: TeamState.fromJson(map['state'] as Map<String, dynamic>),
      xp: (map['xp'] as int?) ?? 0,
    );
  }

  /// The badges and titles this person has earned and which they wear.
  Future<CosmeticCollection> fetchCosmetics() async {
    final res = await http.get(
      _uri('/season-pass/cosmetics'),
      headers: await _authHeaders(),
    );
    await _throwWithDetail(res);
    return CosmeticCollection.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  /// Chooses what to wear; null takes that kind off.
  Future<CosmeticCollection> equipCosmetics({
    int? badgeId,
    int? titleId,
    int? frameId,
  }) async {
    final res = await http.put(
      _uri('/season-pass/cosmetics/equip'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'badge_id': badgeId,
        'title_id': titleId,
        'frame_id': frameId,
      }),
    );
    await _throwWithDetail(res);
    return CosmeticCollection.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  /// Takes a level's reward ([track] is 'free' or 'premium'); returns the
  /// refreshed pass, or throws an [ApiException] with the reason.
  Future<SeasonPass> claimPassLevel(int level, String track) async {
    final res = await http.post(
      _uri('/season-pass/claim'),
      headers: await _authHeaders(),
      body: jsonEncode({'level': level, 'track': track}),
    );
    await _throwWithDetail(res);
    return SeasonPass.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<SeasonPass> claimPassTask(String taskId) async {
    final res = await http.post(
      _uri('/season-pass/tasks/claim'),
      headers: await _authHeaders(),
      body: jsonEncode({'task_id': taskId}),
    );
    await _throwWithDetail(res);
    return SeasonPass.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  /// The check shown before a lesson's first pass (null on any failure: the
  /// lesson then simply starts without it).
  Future<WordCheck?> fetchWordCheck(int lessonId) async {
    try {
      final res = await http.get(
        _uri('/lessons/$lessonId/check'),
        headers: await _authHeaders(),
      );
      if (res.statusCode >= 400) return null;
      return WordCheck.fromJson(
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  /// Sends one check answer; returns whether it was right (null: not sent).
  Future<bool?> answerWordCheck(
    int lessonId, {
    required int wordId,
    required int? pickedWordId,
    CheckRating? rating,
    int? durationMs,
  }) async {
    try {
      final res = await http.post(
        _uri('/lessons/$lessonId/check/answers'),
        headers: await _authHeaders(),
        body: jsonEncode({
          'word_id': wordId,
          'picked_word_id': pickedWordId,
          'rating': rating?.name,
          'duration_ms': durationMs,
        }),
      );
      if (res.statusCode >= 400) return null;
      return (jsonDecode(utf8.decode(res.bodyBytes))
              as Map<String, dynamic>)['is_correct']
          as bool;
    } catch (_) {
      return null;
    }
  }

  Future<void> finishWordCheck(int lessonId) async {
    try {
      await http.post(
        _uri('/lessons/$lessonId/check/finish'),
        headers: await _authHeaders(),
      );
    } catch (_) {}
  }

  Future<Lesson> startLessonPass(int lessonId) async {
    final res = await http.post(
      _uri('/lessons/$lessonId/pass'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return Lesson.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  /// Pass exactly one of [wordIds] (ручной выбор, max 15) or [randomCount]
  /// (случайный выбор, 1-15) -- the backend rejects both/neither, same rule
  /// CreateLessonIn enforces. Fails with a 409 (surfaced via [ApiException.
  /// message]) if the current lesson for this dictionary isn't complete yet,
  /// or a 429 once the daily/weekly lesson limit is reached.
  Future<Lesson> createLesson({
    required int dictionaryId,
    List<int>? wordIds,
    int? randomCount,
  }) async {
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
    return Lesson.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<TrueOrFalseRound> fetchLessonTrueOrFalseRound(
    int lessonId, {
    Iterable<int>? wordIds,
  }) async {
    final res = await http.get(
      _lessonRoundUri(lessonId, 'true-or-false', wordIds),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return TrueOrFalseRound.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  /// Same generic shape as [fetchExerciseLearnedWords], sourced from this
  /// lesson's fixed word set instead of the dictionary's learned words.
  Future<List<GuyoWord>> fetchLessonMatchingWords(
    int lessonId, {
    Iterable<int>? wordIds,
  }) async {
    final res = await http.get(
      _lessonRoundUri(lessonId, 'matching', wordIds),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final list = body['words'] as List<dynamic>;
    return list
        .map((e) => GuyoWord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<BuildWordRound> fetchLessonBuildWordRound(
    int lessonId, {
    Iterable<int>? wordIds,
  }) async {
    final res = await http.get(
      _lessonRoundUri(lessonId, 'build-word', wordIds),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return BuildWordRound.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<SpeakingWordRound> fetchLessonSpeakingWordRound(
    int lessonId, {
    Iterable<int>? wordIds,
  }) async {
    final res = await http.get(
      _lessonRoundUri(lessonId, 'speaking-word', wordIds),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return SpeakingWordRound.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<ListenWordRound> fetchLessonListenWordRound(
    int lessonId, {
    Iterable<int>? wordIds,
  }) async {
    final res = await http.get(
      _lessonRoundUri(lessonId, 'listen-word', wordIds),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return ListenWordRound.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
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

  Future<TrueOrFalseRound> fetchPracticeTrueOrFalseRound(
    int dictionaryId,
  ) async {
    final res = await http.get(
      _uri('/dictionaries/$dictionaryId/practice/true-or-false'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return TrueOrFalseRound.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<List<GuyoWord>> fetchPracticeMatchingWords(int dictionaryId) async {
    final res = await http.get(
      _uri('/dictionaries/$dictionaryId/practice/matching'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final list = body['words'] as List<dynamic>;
    return list
        .map((e) => GuyoWord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// "Повторить сегодня": how many learned words are being forgotten, and
  /// the most forgotten ones (GET .../practice/review-due).
  Future<(int, List<int>)> fetchReviewDue(int dictionaryId) async {
    final res = await http.get(
      _uri('/dictionaries/$dictionaryId/practice/review-due'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return (
      json['count'] as int,
      [for (final id in json['word_ids'] as List<dynamic>) id as int],
    );
  }

  Future<BuildWordRound> fetchPracticeBuildWordRound(
    int dictionaryId, {
    List<int>? wordIds,
  }) async {
    final uri = _uri('/dictionaries/$dictionaryId/practice/build-word');
    final res = await http.get(
      wordIds == null || wordIds.isEmpty
          ? uri
          : uri.replace(
              queryParameters: {
                'word_ids': [for (final id in wordIds) '$id'],
              },
            ),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return BuildWordRound.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<SpeakingWordRound> fetchPracticeSpeakingWordRound(
    int dictionaryId,
  ) async {
    final res = await http.get(
      _uri('/dictionaries/$dictionaryId/practice/speaking-word'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return SpeakingWordRound.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<ListenWordRound> fetchPracticeListenWordRound(int dictionaryId) async {
    final res = await http.get(
      _uri('/dictionaries/$dictionaryId/practice/listen-word'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return ListenWordRound.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
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
    return SubmitAnswerResult.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  final Set<Future<void>> _pendingLessonAnswers = {};

  /// Sends a lesson answer in the background: the exercise moves on at
  /// once (it already judged the answer itself) and the server gets it a
  /// moment later -- tried twice, then given up on. [flushLessonAnswers]
  /// waits for whatever is still on its way.
  Uri _lessonRoundUri(int lessonId, String path, Iterable<int>? wordIds) {
    final uri = _uri('/lessons/$lessonId/exercises/$path');
    if (wordIds == null) return uri;
    return uri.replace(
      queryParameters: {...uri.queryParameters, 'word_ids': wordIds.join(',')},
    );
  }

  /// Each word's latest answer in the current pass of a lesson: the words
  /// whose latest answer is wrong are asked again at the end of the pass.
  final Map<int, Map<int, bool>> _passAnswers = {};

  void startLessonAnswers(int lessonId) => _passAnswers[lessonId] = {};

  /// Words answered wrong (latest answer) in this lesson's current pass.
  Set<int> lessonMistakes(int lessonId) => {
    for (final e in (_passAnswers[lessonId] ?? const <int, bool>{}).entries)
      if (!e.value) e.key,
  };

  void queueLessonAnswer(
    int lessonId,
    String exerciseKey, {
    required int wordId,
    required bool isCorrect,
  }) {
    (_passAnswers[lessonId] ??= {})[wordId] = isCorrect;
    // Taken now, before the next question resets them.
    final signals = AnswerSignals.take();
    final deferred = deferredLessonId == lessonId;
    Future<void> send() async {
      final res = await http.post(
        _uri('/lessons/$lessonId/exercises/$exerciseKey/answers'),
        headers: await _authHeaders(),
        body: jsonEncode({
          ...signals,
          'word_id': wordId,
          'is_correct': isCorrect,
          if (deferred) 'deferred': true,
        }),
      );
      await _throwWithDetail(res);
    }

    late final Future<void> job;
    job = send()
        .catchError(
          (_) => Future<void>.delayed(const Duration(seconds: 1), send),
        )
        .catchError((_) {})
        .whenComplete(() => _pendingLessonAnswers.remove(job));
    _pendingLessonAnswers.add(job);
  }

  Future<void> flushLessonAnswers() =>
      Future.wait(List<Future<void>>.of(_pendingLessonAnswers));

  // --- Профиль и Достижения ------------------------------------------------
  // Avatar storage and achievement earning/eligibility are entirely
  // backend-decided (see backend/app/achievements/) -- this client only
  // fetches/uploads and renders the result.

  Future<UserProfile> fetchMyProfile() async {
    final res = await http.get(
      _uri('/users/me/profile'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    final profile = UserProfile.fromJson(
      _remember('profile', res) as Map<String, dynamic>,
    );
    setStreakState(
      litToday: profile.streakActiveToday,
      days: profile.currentStreakDays,
    );
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
    final res = await http.get(
      _uri('/slogans/today'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return body['text'] as String?;
  }

  /// Premium status, the payment text the admin wrote, and today's/this
  /// week's lesson counter -- everything Главная's counter and the Premium
  /// screen show, in one call.
  Future<PremiumStatus> fetchPremiumStatus() async {
    final res = await http.get(
      _uri('/premium/me'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return PremiumStatus.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
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
    return PromoResult.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  /// Everything in this user's inbox, newest first, with the unread count
  /// the bell's dot is drawn from.
  Future<NotificationInbox> fetchNotifications() async {
    final res = await http.get(
      _uri('/notifications'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return NotificationInbox.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
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
      body: jsonEncode({
        ...signals,
        'word_id': wordId,
        'exercise_key': exerciseKey,
        'is_correct': isCorrect,
      }),
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
      final data =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return data['available'] as bool;
    } catch (_) {
      return null;
    }
  }

  /// The times of day the user picked to study (reminders go out at each).
  Future<List<StudyTime>> fetchStudyTimes() async {
    final res = await http.get(
      _uri('/notifications/study-times'),
      headers: await _authHeaders(),
    );
    await _throwWithDetail(res);
    return _parseStudyTimes(_remember('study-times', res));
  }

  /// Replaces the whole list; returns what the server stored.
  Future<List<StudyTime>> saveStudyTimes(List<StudyTime> times) async {
    final res = await http.put(
      _uri('/notifications/study-times'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'times': [for (final t in times) t.toJson()],
      }),
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
    final res = await http.get(
      _uri('/notifications/unread-count'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return body['unread_count'] as int;
  }

  /// Marks every message read and returns the refreshed inbox.
  Future<NotificationInbox> markAllNotificationsRead() async {
    final res = await http.post(
      _uri('/notifications/read-all'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return NotificationInbox.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
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
    String? learningLanguage,
  }) async {
    final body = <String, dynamic>{
      if (login != null) 'login': login,
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (email != null) 'email': email,
      if (learningTopics != null) 'learning_topics': learningTopics,
      if (uiLanguage != null) 'ui_language': uiLanguage,
      if (translationLanguage != null)
        'translation_language': translationLanguage,
      if (learningLanguage != null) 'learning_language': learningLanguage,
    };
    final res = await http.patch(
      _uri('/users/me/profile'),
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    // _throwWithDetail, not the plain check: a taken login or email comes
    // back as a 409 whose own message is the only useful thing to show.
    await _throwWithDetail(res);
    return UserProfile.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
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
  Future<UserProfile> uploadMyAvatar(
    List<int> bytes,
    String filename, {
    String? mimeType,
  }) async {
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
      onTimeout: () => throw ApiException(
        tr('Загрузка не удалась: слишком медленное соединение'),
      ),
    );
    final res = await http.Response.fromStream(streamed)
        .timeout(const Duration(seconds: 25));
    await _throwWithDetail(res);
    return UserProfile.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  /// Clears the avatar -- the caller should fall back to the generated
  /// default avatar the moment `avatarUrl` comes back null.
  Future<UserProfile> deleteMyAvatar() async {
    final res = await http
        .delete(_uri('/users/me/avatar'), headers: await _authHeaders())
        .timeout(const Duration(seconds: 15));
    await _throwIfUnauthorized(res);
    return UserProfile.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<List<UserAchievement>> fetchMyAchievements() async {
    final res = await http.get(
      _uri('/users/me/achievements'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    final list = _remember('achievements', res) as List<dynamic>;
    return list
        .map((e) => UserAchievement.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The Статистика screen's data (GET /users/me/stats), for a 7 or 30 day chart.
  Future<UserStats> fetchMyStats(int days) async {
    final res = await http.get(
      _uri('/users/me/stats').replace(queryParameters: {'days': '$days'}),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    if (res.statusCode != 200)
      throw ApiException(
        'Не удалось загрузить статистику',
        statusCode: res.statusCode,
      );
    return UserStats.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  /// Earned but not yet shown to this account (GET /users/me/achievements/new).
  Future<List<UserAchievement>> fetchNewAchievements() async {
    final res = await http.get(
      _uri('/users/me/achievements/new'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    if (res.statusCode != 200)
      throw ApiException(
        'Не удалось загрузить достижения',
        statusCode: res.statusCode,
      );
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list
        .map((e) => UserAchievement.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Records on the server that these achievements were celebrated.
  Future<void> markAchievementsSeen(List<int> ids) async {
    final res = await http.post(
      _uri('/users/me/achievements/seen'),
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({'ids': ids}),
    );
    await _throwIfUnauthorized(res);
    if (res.statusCode >= 300)
      throw ApiException('Не удалось сохранить', statusCode: res.statusCode);
  }

  /// A fully separate system from achievements (see backend/app/rating/) --
  /// current points, current season, current rank and season history, all
  /// backend-decided.
  Future<UserRating> fetchMyRating() async {
    final res = await http.get(
      _uri('/users/me/rating'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return UserRating.fromJson(
      _remember('rating', res) as Map<String, dynamic>,
    );
  }

  /// Top 100 users sharing the CALLER's own current rank -- the backend
  /// decides which rank that is; there is no way to ask for a different
  /// one.
  Future<Leaderboard> fetchMyRankLeaderboard() async {
    final res = await http.get(
      _uri('/rating/leaderboard'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return Leaderboard.fromJson(
      _remember('leaderboard', res) as Map<String, dynamic>,
    );
  }

  /// The word-reinforcement ladder, enabled levels only, lowest
  /// score-range first -- see WordLevelSummary's own doc.
  Future<List<WordLevelSummary>> fetchWordLevels() async {
    final res = await http.get(
      _uri('/word-levels'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return _parseWordLevels(_remember('word-levels', res));
  }

  /// What the status picker offers, plus the user's current status.
  Future<StatusOptions> fetchStatusOptions() async {
    final res = await http.get(
      _uri('/status/options'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    if (res.statusCode != 200)
      throw ApiException(
        tr('Не удалось загрузить статусы'),
        statusCode: res.statusCode,
      );
    return StatusOptions.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  /// Sets both parts of the leaderboard status; null clears a part.
  Future<MyStatus> updateMyStatus({int? emojiId, int? phraseId}) async {
    final res = await http.put(
      _uri('/status/me'),
      headers: await _authHeaders(),
      body: jsonEncode({'emoji_id': emojiId, 'phrase_id': phraseId}),
    );
    await _throwIfUnauthorized(res);
    if (res.statusCode != 200)
      throw ApiException(
        tr('Не удалось сохранить статус'),
        statusCode: res.statusCode,
      );
    return MyStatus.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  /// Top 100 users across every rank combined.
  /// The caller and their friends, by points (GET /rating/leaderboard/friends).
  Future<Leaderboard> fetchFriendsLeaderboard() async {
    final res = await http.get(
      _uri('/rating/leaderboard/friends'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return Leaderboard.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  /// Who a 9-digit ID belongs to (GET /rating/users/{id}) -- shown before
  /// adding a friend.
  Future<FoundUser> findUserByPublicId(int publicId) async {
    final res = await http.get(
      _uri('/rating/users/$publicId'),
      headers: await _authHeaders(),
    );
    await _throwWithDetail(res);
    return FoundUser.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
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
    final res = await http.delete(
      _uri('/rating/friends/$userId'),
      headers: await _authHeaders(),
    );
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
    final res = await http.get(
      _uri('/rating/leaderboard/global'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return Leaderboard.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  /// The full rank ladder, enabled ranks only, lowest points-requirement
  /// first -- what the Profile screen's "Все уровни" full-progress-path
  /// screen renders. The SAME ranks/order fetchMyRating's own rank/
  /// next_rank came from, never a second definition of the ladder.
  Future<List<RankSummary>> fetchAllRanks() async {
    final res = await http.get(
      _uri('/rating/ranks'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return _parseRanks(_remember('ranks', res));
  }

  // --- Квесты ---------------------------------------------------------------
  // A system entirely separate from Lessons (see backend/app/quests/) --
  // eligibility, round content, and reward are all backend-decided.

  Future<List<AvailableQuest>> fetchAvailableQuests(int dictionaryId) async {
    final res = await http.get(
      _uri('/quests')
          .replace(queryParameters: {'dictionary_id': '$dictionaryId'}),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list
        .map((e) => AvailableQuest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Everything the "Квесты сезона" block on Главная and the season
  /// quests screen need, in one round trip -- the active season with its
  /// admin-uploaded icon, this user's rating standing, and their quest
  /// progress today. A read-only view over the season/rating/quest
  /// systems that already exist; nothing here is a second source of any
  /// of those numbers.
  Future<SeasonQuestOverview> fetchSeasonQuestOverview(int dictionaryId) async {
    final res = await http.get(
      _uri('/quests/overview')
          .replace(queryParameters: {'dictionary_id': '$dictionaryId'}),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    return SeasonQuestOverview.fromJson(
      _remember('overview-$dictionaryId', res) as Map<String, dynamic>,
    );
  }

  /// Today's points, grant by grant, newest first (GET /quests/points-today).
  Future<List<PointsTodayItem>> fetchPointsToday() async {
    final res = await http.get(
      _uri('/quests/points-today'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    if (res.statusCode != 200)
      throw ApiException(
        'Не удалось загрузить историю',
        statusCode: res.statusCode,
      );
    return (jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>)
        .map((e) => PointsTodayItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The streak sheet's data (GET /users/me/streak).
  Future<StreakInfo> fetchMyStreak() async {
    final res = await http.get(
      _uri('/users/me/streak'),
      headers: await _authHeaders(),
    );
    await _throwIfUnauthorized(res);
    if (res.statusCode != 200)
      throw ApiException(
        'Не удалось загрузить серию',
        statusCode: res.statusCode,
      );
    return _parseStreak(_remember('streak', res));
  }

  Future<QuestRound> fetchQuestRound(int questId, int dictionaryId) async {
    final res = await http.get(
      _uri('/quests/$questId/round')
          .replace(queryParameters: {'dictionary_id': '$dictionaryId'}),
      headers: await _authHeaders(),
    );
    await _throwWithDetail(res);
    return QuestRound.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<QuestAnswerResult> submitQuestAnswer(
    int questId,
    int dictionaryId, {
    required int wordId,
    required bool isCorrect,
  }) async {
    final signals = AnswerSignals.take();
    final res = await http.post(
      _uri('/quests/$questId/answers')
          .replace(queryParameters: {'dictionary_id': '$dictionaryId'}),
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({
        ...signals,
        'word_id': wordId,
        'is_correct': isCorrect,
      }),
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
    final res = await http.get(
      _uri('/text-check/info'),
      headers: await _authHeaders(),
    );
    await _throwWithDetail(res);
    return TextCheckInfo.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
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
    return TextCheckResult.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }
}
