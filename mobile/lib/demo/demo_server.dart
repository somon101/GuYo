import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'demo_lessons.dart';
import 'demo_state.dart';
import 'demo_words.dart';

/// A fake backend for the demo build: answers the main screens with made-up data, so the
/// app can be looked at with no server. Nothing here is used by the real app.
http.Client demoClient() => MockClient((req) async {
      final path = req.url.path;
      Object? body;
      Map<String, dynamic> sent = {};
      try {
        if (req.body.isNotEmpty) sent = jsonDecode(req.body) as Map<String, dynamic>;
      } catch (_) {}
      body = demoDynamic(req.method, path, req.url.queryParameters, sent);
      if (body == null) {
        if (req.method == 'GET') {
          body = _get(path, req.url.queryParameters);
        } else if (path.startsWith('/auth/')) {
          body = {'access_token': 'demo', 'token_type': 'bearer'}; // any login and password gets in
        } else {
          body = {'ok': true};
        }
      }
      if (body == null || identical(body, demoNotFound)) return http.Response('{"detail":"demo"}', 404, headers: _h);
      return http.Response(jsonEncode(body), 200, headers: _h);
    });

const _h = {'content-type': 'application/json; charset=utf-8'};

String _in(int days) => DateTime.now().add(Duration(days: days)).toUtc().toIso8601String();
String _day(int ago) {
  final d = DateTime.now().subtract(Duration(days: ago));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

Object? _get(String path, Map<String, String> q) {
  switch (path) {
    case '/users/me':
    case '/users/me/profile':
      return {
        'id': 1, 'public_id': 123456789, 'login': 'Demo', 'first_name': 'Демо', 'last_name': null, 'email': null,
        'avatar_url': null, 'current_streak_days': 13, 'streak_active_today': true, 'lessons_completed': 42,
        'words_learned': 318, 'premium_until': _in(20), 'learning_topics': <String>[], 'ui_language': 'ru',
        'translation_language': 'tg', 'learning_language': 'en', 'language_unavailable': <String>[],
      };
    case '/slogans/today':
      return {'text': 'Каждый день по чуть-чуть', 'slogan': 'Каждый день по чуть-чуть'};
    case '/users/me/achievements':
      return [
        for (final a in _achievements)
          {
            'id': a.$1, 'title': a.$2, 'description': a.$3, 'icon_url': null, 'color': a.$4,
            'condition_type': 'words_learned', 'condition_value': a.$5, 'earned': a.$6,
            'earned_at': a.$6 ? _in(-a.$1) : null, 'current_value': a.$6 ? a.$5 : a.$5 ~/ 2,
          },
      ];
    case '/users/me/achievements/new':
      return <Object>[];
    case '/users/me/rating':
      return {
        'total_points': 1240, 'season': {'id': 1, 'name': 'Осень', 'status': 'active', 'starts_at': _in(-10), 'ends_at': _in(30)},
        'rank': _rank(2), 'next_rank': _rank(3), 'points_to_next_rank': 260,
        'history': [
          {'season_id': 0, 'season_name': 'Лето', 'points': 980, 'rank': _rank(1), 'ended_at': _in(-15)},
        ],
        'points_per_learned_word': 5, 'rank_position': 7, 'position_change': 1,
      };
    case '/rating/ranks':
      return [for (var i = 1; i <= 4; i++) _rank(i)];
    case '/rating/leaderboard':
    case '/rating/leaderboard/global':
    case '/rating/leaderboard/friends':
      return {
        'rank': path.endsWith('global') ? null : _rank(2),
        'entries': [
          for (var i = 0; i < _people.length; i++)
            {
              'position': i + 1, 'user_id': i + 1, 'login': _people[i].$1, 'avatar_url': null, 'total_points': _people[i].$2,
              'rank': path.endsWith('global') || path.endsWith('friends') ? _rank(2) : _rank(2),
              'is_me': _people[i].$1 == 'Demo', 'is_premium': _people[i].$1 == 'Demo', 'position_change': i % 3 - 1,
            },
        ],
      };
    case '/word-levels':
      return [
        {'id': 1, 'name': 'Новое'}, {'id': 2, 'name': 'Знакомое'}, {'id': 3, 'name': 'Уверенное'}, {'id': 4, 'name': 'Выучено'},
      ];
    case '/users/me/stats':
      return {
        'accuracy': 87, 'total_answers': 640,
        'exercises': [
          {'exercise_key': 'true_or_false', 'correct': 90, 'total': 100},
          {'exercise_key': 'matching', 'correct': 80, 'total': 100},
          {'exercise_key': 'build_word', 'correct': 70, 'total': 90},
        ],
        'points_chart': [for (var i = 6; i >= 0; i--) {'date': _day(i), 'points': 40 + (i * 13) % 50}],
        'points_total': 330, 'points_prev_total': 280,
        'calendar': [for (var i = 29; i >= 0; i--) {'date': _day(i), 'active': i < 13 || i % 3 == 0, 'answers': i < 13 ? 30 : 12}],
        'current_streak': 13, 'best_streak': 21, 'lessons_completed': 42, 'words_learned': 318, 'words_learned_week': 54,
        'time_minutes': 960, 'time_week_minutes': 130, 'avg_answer_seconds': 3.4, 'best_weekday': 2,
        'hard_words': [
          {'word_id': 1, 'word': 'apple', 'dictionary_id': 1, 'mistakes': 4},
          {'word_id': 2, 'word': 'bread', 'dictionary_id': 1, 'mistakes': 3},
        ],
      };
    case '/status/options':
      return {'emojis': <Object>[], 'phrases': <Object>[], 'mine': {}, 'premium': true};
    case '/status/me':
      return {};
    case '/auth/login-available':
      return {'available': true};
    case '/languages':
      return [
        {'code': 'en', 'name': 'English', 'native_name': 'English'},
        {'code': 'tg', 'name': 'Tajik', 'native_name': 'Тоҷикӣ'},
      ];
    case '/dictionaries':
      return [
        {'id': 1, 'name': 'Еда', 'language': 'en', 'word_count': 20},
        {'id': 2, 'name': 'Путешествия', 'language': 'en', 'word_count': 20},
      ];
    case '/shop':
      return {'diamonds': 240, 'products': <Object>[]};
    case '/chests':
      return {
        'types': [
          {'key': 'wood', 'name': 'Деревянный', 'color': '#A9743B'},
          {'key': 'silver', 'name': 'Серебряный', 'color': '#9AA4B2'},
          {'key': 'gold', 'name': 'Золотой', 'color': '#E7B73C'},
          {'key': 'diamond', 'name': 'Алмазный', 'color': '#5BC8F5'},
        ],
        'chests': [
          for (var i = 0; i < 6; i++) {'id': i + 1, 'chest_key': i < 3 ? 'wood' : i < 5 ? 'silver' : 'gold', 'source': 'lesson'},
        ],
        'daily': {'enabled': true, 'available': true, 'claimed': false, 'chest_key': 'wood', 'conditions': ''},
        'double': false, 'inventory_max': 10, 'booster_qty': 2,
      };
    case '/boosters':
      return {
        'items': [{'minutes': 30, 'qty': 2}], 'active_until': null,
        'kinds': {
          'rating': {'items': [{'minutes': 30, 'qty': 1}], 'active_until': null},
          'xp': {'items': <Object>[], 'active_until': null},
        },
      };
    case '/duels':
      return {
        'enabled': true, 'rewards': <String, Object>{}, 'recent': <Object>[],
        'current': {
          'id': 1, 'status': 'active', 'ends_at': _in(4), 'i_challenged': true, 'opponent_id': 2,
          'opponent_login': 'Aziz', 'opponent_avatar_url': null, 'my_xp': 328, 'their_xp': 290, 'won': null,
        },
      };
    case '/season-pass':
    case '/season-pass/summary':
      return {
        'season_name': 'Осень', 'ends_at': _in(30), 'xp': 140, 'level': 4, 'xp_into_level': 40, 'xp_for_next': 100,
        'is_premium': true, 'premium_enabled': true,
        'levels': [
          for (var l = 1; l <= 10; l++)
            {
              'level': l, 'xp': l * 100,
              'free': {'type': 'xp', 'amount': 10, 'kind': 'chest', 'claimed': l < 4, 'claimable': l == 4},
              'premium': {'type': 'diamonds', 'amount': 5, 'kind': 'chest', 'claimed': l < 4, 'claimable': l == 4},
            },
        ],
        'week': {'ends_at': _in(3), 'tasks': <Object>[]},
      };
    case '/quests/overview':
      return {
        'season': {'id': 1, 'name': 'Осень', 'icon_url': null, 'starts_at': _in(-10), 'ends_at': _in(30)},
        'days_left': 30, 'days_total': 40, 'points_today': 60, 'total_points': 1240, 'rank': null, 'rank_position': 7,
        'quests_done_today': 3, 'quests_total': 5, 'points_per_learned_word': 5, 'words_learned_today': 12, 'quests': <Object>[],
      };
    case '/premium/me':
      return {
        'is_premium': true, 'premium_until': _in(20), 'premium_enabled': true, 'public_id': 123456789,
        'price_text': '', 'payment_instructions': '',
        'lessons': {'daily_limit': null, 'daily_used': 0, 'weekly_limit': null, 'weekly_used': 0, 'remaining': null, 'blocked_by': null},
      };
    case '/users/me/streak':
      return {
        'current_streak_days': 13, 'today': _day(0), 'active_dates': [for (var i = 0; i < 13; i++) _day(i)],
        'frozen_dates': <String>[], 'freezes': 1, 'merged_days': 0, 'streak_merge_items': 0,
      };
    case '/notifications/unread-count':
      return {'count': 2, 'unread_count': 2};
    case '/notifications':
      return {'unread_count': 0, 'items': <Object>[], 'notifications': <Object>[]};
    case '/users/me/progress':
      return {'total_words': 318, 'total_active_days': 30, 'weeks': <Object>[]};
    case '/learned-words':
      final dict = int.tryParse(q['dictionary_id'] ?? '') ?? 1;
      final cat = int.tryParse(q['category_id'] ?? '');
      return [
        for (final w in DemoState.instance.learnedWords(dict))
          if (cat == null || w.categoryId == cat) wordJson(w, progress: q['include_in_progress'] == 'true'),
      ];
    case '/learned-words/categories':
      final dict = int.tryParse(q['dictionary_id'] ?? '') ?? 1;
      final counts = <int, int>{};
      for (final w in DemoState.instance.learnedWords(dict)) {
        counts[w.categoryId] = (counts[w.categoryId] ?? 0) + 1;
      }
      return [
        for (final e in counts.entries) {'category_id': e.key, 'category_name': demoCategories[e.key], 'learned_count': e.value, 'icon_url': null},
      ];
    default:
      final dm = RegExp(r'^/dictionaries/(\d+)/(words|available-phrases)$').firstMatch(path);
      if (dm != null) {
        final dict = int.parse(dm.group(1)!);
        return dm.group(2) == 'words'
            ? [for (final w in wordsOf(dict)) wordJson(w)]
            : [for (final p in demoPhrases) if (p.$2 == dict) phraseJson(p)];
      }
      if (path.startsWith('/season-pass') || path == '/gifts' || path == '/teams/me') return null;
      return null;
  }
}

Map<String, Object?> _rank(int i) {
  const names = ['Новичок', 'Ученик', 'Знаток', 'Мастер'];
  const colors = ['#A9743B', '#9AA4B2', '#E7B73C', '#5BC8F5'];
  return {'id': i, 'name': names[(i - 1) % 4], 'icon_url': null, 'color': colors[(i - 1) % 4], 'min_points': (i - 1) * 500, 'max_points': i == 4 ? null : i * 500 - 1};
}

const _people = [
  ('Aziz', 1840), ('Madina', 1620), ('Rustam', 1500), ('Nilufar', 1410), ('Jasur', 1330), ('Zarina', 1290), ('Demo', 1240), ('Sardor', 1100), ('Malika', 980),
];

const _achievements = [
  (1, 'Первые шаги', 'Выучите 10 слов', '#5862DD', 10, true),
  (2, 'Начитанный', 'Выучите 100 слов', '#8B5CF6', 100, true),
  (3, 'Знаток слов', 'Выучите 300 слов', '#E7B73C', 300, true),
  (4, 'Словарный запас', 'Выучите 500 слов', '#16A34A', 500, false),
  (5, 'Эрудит', 'Выучите 1000 слов', '#F97316', 1000, false),
];
