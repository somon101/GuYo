// The social store of the real app: it reads the server's answers (the feed, the requests, the teams),
// shows a change at once and takes it back when the server refuses.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/api/api_client.dart';
import 'package:guyo_app/demo/demo_server.dart';
import 'package:guyo_app/social/server_social.dart';
import 'package:guyo_app/social/social_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object?> _person(int id, String login, {bool premium = false}) => {'user_id': id, 'login': login, 'avatar_url': null, 'avatar_look': null, 'is_premium': premium};

Map<String, Object?> _card(int id, Map<String, Object?> person, String kind, Map<String, Object?> data, {bool friend = false, bool liked = false, int likes = 3, String? mine, List<Map<String, Object?>> likers = const [], Map<String, Object?>? last, int? views}) => {
      'id': id,
      'kind': kind,
      'data': data,
      'created_at': DateTime.now().toUtc().subtract(const Duration(hours: 3)).toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'person': person,
      'is_mine': false,
      'is_friend': friend,
      'likes': likes,
      'comments': mine == null ? 1 : 2,
      'liked': liked,
      'my_comment': mine,
      'likers': likers,
      'last_comment': last,
      'views': views,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (_) async => null);

  final demo = demoClient();
  final calls = <String>[];
  var refuseLike = false;

  http.Response json(Object? body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  final client = MockClient((req) async {
    final path = req.url.path;
    final key = '${req.method} $path${req.url.hasQuery ? '?${req.url.query}' : ''}';
    if (path.startsWith('/feed') || path.startsWith('/friends/requests') || path.startsWith('/teams') || path.startsWith('/people')) calls.add(key);
    if (key == 'GET /feed') {
      return json({
        'cards': [
          _card(1, _person(7, 'Aziz'), 'streak', {'days': 7}, friend: true, likes: 5, likers: [_person(8, 'Madina')], last: {'person': _person(8, 'Madina'), 'phrase': 'Молодец!'}),
          _card(2, _person(9, 'Rustam', premium: true), 'words', {'count': 12}, liked: true, likes: 4, mine: 'Огонь!', likers: [_person(1, 'Demo'), _person(8, 'Madina')], views: 40),
        ],
        'has_more': false,
        'phrases': ['Молодец!', 'Огонь!'],
        'suggestions': [
          {..._person(20, 'Zarina'), 'reason': 'mutual', 'count': 3},
        ],
        'friends_only': false,
      });
    }
    if (key == 'GET /friends/requests') {
      return json({
        'incoming': [_person(30, 'Sardor')],
        'outgoing': [_person(31, 'Malika')],
      });
    }
    if (key == 'GET /teams/open?closed=true') {
      return json([
        {'id': 5, 'name': 'Closed ones', 'members': 3, 'capacity': 5, 'is_open': false, 'requested': true},
      ]);
    }
    if (key == 'GET /teams/me') return json({'team': null, 'invites': [], 'capacity': 5, 'my_requests': [5], 'requests': [_person(40, 'Asker')]});
    if (key == 'POST /feed/1/like' && refuseLike) return json({'detail': 'нет'}, 409);
    if (key.startsWith('POST /feed/') || key.startsWith('DELETE /feed/')) return json({'ok': true});
    if (key == 'POST /friends/requests') return json({'user_id': 20, 'relation': 'sent'});
    if (key == 'GET /people/20') {
      return json({
        'user_id': 20, 'login': 'Zarina', 'avatar_url': null, 'is_premium': false, 'rank': 'Мастер', 'total_points': 1290, 'relation': 'none',
        'achievements_earned': 3, 'achievements_total': 12, 'week_points': [1, 2, 3, 4, 5, 6, 7],
        'habits': {'hours': '14–16', 'best_day': 3, 'accuracy': 92, 'avg_answer': 2.5},
        'studying': ['Английский'],
        'team': {'id': 5, 'name': 'Closed ones', 'is_open': false, 'members': 3, 'capacity': 5, 'is_mine': false, 'requested': true},
      });
    }
    final again = http.Request(req.method, req.url)
      ..headers.addAll(req.headers)
      ..bodyBytes = req.bodyBytes;
    return http.Response.fromStream(await demo.send(again));
  });

  test('the feed, the requests and the teams come from the server and are read as they are', () async {
    await http.runWithClient(() async {
      await ApiClient.instance.login('demo', 'demo');
      final s = ServerSocial();
      SocialStore.instance = s;
      await s.refresh();

      expect(s.me, isNonZero);
      expect(s.cards.map((c) => c.id), [1, 2]);
      final streak = s.cards.first;
      expect(streak.title, contains('7'));
      expect(s.isFriend(7), isTrue); // the card said the author is a friend
      expect(streak.lastComment, (8, 'Молодец!'));
      expect(streak.views, isNull);
      final words = s.cards[1];
      expect(words.liked, isTrue);
      expect(words.myComment, 'Огонь!');
      expect(words.likeCount, 4); // the server's 4 already include the player's own heart
      expect(words.commentCount, 2);
      expect(words.likers, [8]); // the player is not in the list of «others»
      expect(words.views, 40);
      expect(s.phrases, ['Молодец!', 'Огонь!']);
      expect(s.suggestions.single.$1, 20);
      expect(s.incomingRequests, [30]);
      expect(s.friendRequests, {31});
      expect(s.teamAskers, [40]);
      expect(s.teamRequests, {5});
      expect(s.teams[5]!.isOpen, isFalse);
      expect(s.teams[5]!.count, 3);
    }, () => client);
  });

  test('a heart shows at once, goes to the server, and is taken back when the server refuses', () async {
    await http.runWithClient(() async {
      await ApiClient.instance.login('demo', 'demo');
      final s = ServerSocial();
      await s.refresh();
      final c = s.cards.first;
      calls.clear();
      await s.toggleLike(c);
      expect(c.liked, isTrue);
      expect(calls, contains('POST /feed/1/like'));
      refuseLike = true;
      await s.toggleLike(s.cards[1]); // un-like is fine
      expect(s.cards[1].liked, isFalse);
      await s.toggleLike(s.cards[1]);
      expect(s.cards[1].liked, isTrue);
      c.liked = false;
      await expectLater(s.toggleLike(c), throwsA(isA<SocialError>()));
      expect(c.liked, isFalse); // taken back
      refuseLike = false;
    }, () => client);
  });

  test('a friend request goes out and a person is opened with the profile of the server', () async {
    await http.runWithClient(() async {
      await ApiClient.instance.login('demo', 'demo');
      final s = ServerSocial();
      await s.refresh();
      await s.toggleFriendRequest(20);
      expect(s.friendRequests, contains(20));
      expect(calls.last, 'POST /friends/requests');
      await s.ensurePerson(20);
      final p = s.people[20]!;
      expect(p.rank, 'Мастер');
      expect(p.points, 1290);
      expect(p.achievements, 3);
      expect(p.achievementsTotal, 12);
      expect(p.week, [1, 2, 3, 4, 5, 6, 7]);
      expect(p.hours, '14–16');
      expect(p.bestDay, 'четверг');
      expect(p.avgAnswer, '2,5');
      expect(p.studying, 'Английский');
      expect(s.friendRequests, isNot(contains(20))); // the server says there is no request
      expect(s.teams[5]!.count, 3);
    }, () => client);
  });
}
