import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A fake backend for the demo build: answers the main screens with made-up data, so the
/// app can be looked at with no server. Nothing here is used by the real app.
http.Client demoClient() => MockClient((req) async {
      final path = req.url.path;
      Object? body;
      if (req.method == 'GET') body = _get(path, req.url.queryParameters);
      body ??= req.method == 'GET' ? null : {'ok': true};
      if (body == null) return http.Response('{"detail":"demo"}', 404, headers: _h);
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
    case '/languages':
      return [
        {'code': 'en', 'name': 'English', 'native_name': 'English'},
        {'code': 'tg', 'name': 'Tajik', 'native_name': 'Тоҷикӣ'},
      ];
    case '/dictionaries':
      return [
        {'id': 1, 'name': 'Еда', 'language': 'en', 'word_count': 60},
        {'id': 2, 'name': 'Путешествия', 'language': 'en', 'word_count': 80},
      ];
    case '/shop':
      return {'diamonds': 240, 'products': <Object>[]};
    case '/daily-goal':
      return {
        'goal': 20, 'done': 12, 'completed': false, 'just_completed': false, 'xp': 0, 'locked': false,
        'reward_ready': false, 'options': [5, 10, 20],
        'tiers': [
          {'words': 20, 'rewards': [{'type': 'xp', 'amount': 20}, {'type': 'chest', 'key': 'wood', 'amount': 1}], 'claimed': false},
        ],
      };
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
    default:
      if (path.endsWith('/practice/review-due')) return {'count': 12, 'word_ids': List.generate(12, (i) => i + 1)};
      if (path.startsWith('/season-pass') || path == '/gifts' || path == '/teams/me') return null;
      return null;
  }
}
