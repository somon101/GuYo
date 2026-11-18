// The demo's people, feed cards, friends and teams. One place, used both by the demo's own screens
// (demo_feed.dart) and by the fake server's team answers, so what the season pass shows under
// «Командные цели» and what the feed shows are the same teams. Nothing here is used by the real app.

import 'dart:async';

import '../social/social_store.dart';
import 'demo_state.dart';

class DemoSocial extends SocialStore {
  DemoSocial._() {
    people.addAll(_people);
    friends.addAll({101, 102});
    cards.addAll(_cards);
    teams.addAll(_teams);
    suggestions = _suggestions;
  }
  static final DemoSocial instance = DemoSocial._();

  /// The player's id inside teams (the same as /users/me).
  @override
  int get me => 1;

  @override
  int? get wordsToday => DemoState.instance.wordsToday;
  @override
  int? get dailyGoal => DemoState.instance.goal;
  @override
  String? get globalWordsToday => '12 480';

  final Map<int, SocialPerson> _people = {
    for (final p in const [
      SocialPerson(101, 'Aziz', 0, 'Мастер', 1840, 9, [60, 90, 40, 120, 30, 80, 70], bestDay: 'четверг', accuracy: 92),
      SocialPerson(102, 'Madina', 1, 'Знаток', 1620, 7, [40, 85, 60, 120, 0, 95, 70], accuracy: 91),
      SocialPerson(103, 'Rustam', 2, 'Знаток', 1500, 5, [20, 40, 75, 60, 90, 10, 50], hours: '7–9 ч', bestDay: 'пятница'),
      SocialPerson(104, 'Nilufar', 5, 'Ученик', 1410, 2, [30, 0, 45, 20, 60, 35, 0], hours: '12–14 ч'),
      SocialPerson(105, 'Jasur', 4, 'Ученик', 1330, 4, [80, 70, 0, 55, 40, 100, 20], bestDay: 'суббота'),
      SocialPerson(106, 'Zarina', 3, 'Мастер', 1290, 11, [100, 60, 80, 110, 70, 0, 90], hours: '21–23 ч', accuracy: 94),
      SocialPerson(108, 'Sardor', 2, 'Ученик', 1100, 3, [10, 30, 40, 0, 50, 20, 30]),
      SocialPerson(109, 'Malika', 3, 'Знаток', 980, 3, [50, 20, 0, 40, 30, 60, 10], hours: '18–20 ч'),
      SocialPerson(110, 'Farrukh', 4, 'Ученик', 1210, 4, [40, 40, 50, 30, 20, 0, 60]),
      SocialPerson(111, 'Dilnoza', 5, 'Новичок', 430, 1, [0, 20, 10, 30, 0, 15, 25]),
      SocialPerson(112, 'Bekzod', 0, 'Ученик', 760, 2, [20, 30, 0, 25, 40, 10, 0]),
      SocialPerson(113, 'Shahlo', 1, 'Знаток', 1520, 12, [90, 80, 70, 100, 60, 80, 110], accuracy: 95),
    ])
      p.id: p,
  };

  /// Why someone is suggested in «Возможно, вы знакомы».
  static const List<(int, String)> _suggestions = [
    (108, '3 общих друга'),
    (109, 'Друг Aziz'),
    (110, 'Ваш ранг, занимается каждый день'),
    (111, 'Учит те же темы'),
  ];

  late final List<SocialCard> _cards = [
    SocialCard(1, 101, 'streak', '7 дней подряд', 'Серия', 'только что', 20, 3, [102, 103, 108, 109, 110, 111, 112, 113], (102, 'Молодец!')),
    SocialCard(2, 102, 'words', 'Выучила сегодня 12 слов', 'Обновляется в течение дня', 'сегодня', 7, 1, [101, 106, 105, 104, 108, 109, 110], (101, 'Так держать!')),
    SocialCard(3, 103, 'gem', '100 слов выучено', 'Достижение «Начитанный»', '2 ч назад', 354, 20, [106, 113, 101, 112, 109, 111, 110, 105], (106, 'Огонь!')),
    SocialCard(4, 106, 'rank', 'Новый ранг: Мастер', 'Рейтинг', '5 ч назад', 2099, 126, [105, 102, 103, 113, 108, 104, 112, 110], (105, 'Горжусь тобой')),
    SocialCard(5, 105, 'duel', 'Победа в дуэли недели', '328 против 290', 'вчера', 61, 5, [104, 101, 111, 109, 108, 113], (104, 'Молодец!')),
    SocialCard(6, 104, 'streak', '3 дня подряд', 'Первая серия', 'вчера', 36, 4, [103, 102, 112, 110, 106, 109], (103, 'Так держать!')),
  ];

  final Map<int, SocialTeam> _teams = {
    1: SocialTeam(1, 'Словарный взвод', true, 101, [101, 108, 109], 62),
    2: SocialTeam(2, 'Ночные совы', false, 106, [106, 105, 113, 112], 80),
    3: SocialTeam(3, 'Утренний урок', false, 102, [102, 103, 111, 110], 71),
    4: SocialTeam(4, 'Без выходных', true, 104, [104, 112, 110, 111, 113], 93),
  };
  int _nextTeamId = 10;

  // --- reactions: kept on the phone ----------------------------------------------------------

  @override
  Future<void> toggleLike(SocialCard c) async {
    c.liked = !c.liked;
    touch();
  }

  @override
  Future<void> setComment(SocialCard c, String phrase) async {
    c.myComment = phrase;
    touch();
  }

  @override
  Future<void> hide(SocialCard c) async {
    hiddenCards.add(c.id);
    touch();
  }

  // --- friends -------------------------------------------------------------------------------

  /// Sends a friend request, or takes it back when one is already waiting.
  @override
  Future<void> toggleFriendRequest(int id) async {
    if (!friendRequests.remove(id)) friendRequests.add(id);
    touch();
  }

  @override
  Future<void> removeFriend(int id) async {
    friends.remove(id);
    touch();
  }

  // --- teams ---------------------------------------------------------------------------------

  @override
  Future<void> join(int teamId) async => joinNow(teamId);

  @override
  Future<void> toggleTeamRequest(int teamId) async {
    if (!teamRequests.remove(teamId)) teamRequests.add(teamId);
    touch();
  }

  @override
  Future<SocialTeam> create(String name, {required bool isOpen}) async => createNow(name, isOpen: isOpen);

  @override
  Future<void> leave() async => leaveNow();

  /// Joins an open team with room at once.
  void joinNow(int teamId) {
    final t = teams[teamId];
    if (t == null || !t.isOpen) throw const SocialError('Эта команда закрыта для вступления');
    if (myTeam != null) throw const SocialError('Вы уже состоите в команде');
    if (roomIn(t) <= 0) throw const SocialError('В команде нет мест');
    t.members.add(me);
    teamRequests.remove(teamId);
    touch();
  }

  SocialTeam createNow(String name, {required bool isOpen}) {
    final n = name.trim();
    if (n.length < 3 || n.length > 24) throw const SocialError('Название команды: от 3 до 24 символов');
    if (myTeam != null) throw const SocialError('Вы уже состоите в команде');
    final t = SocialTeam(_nextTeamId++, n, isOpen, me, [me], 0);
    teams[t.id] = t;
    touch();
    return t;
  }

  void leaveNow() {
    final t = myTeam;
    if (t == null) throw const SocialError('Вы не состоите в команде');
    t.members.remove(me);
    if (t.members.isEmpty) {
      teams.remove(t.id);
    } else if (t.ownerId == me) {
      t.ownerId = t.members.first; // the longest-standing member
    }
    touch();
  }

  void kickNow(int userId) {
    final t = myTeam;
    if (t == null || t.ownerId != me) throw const SocialError('Это может только создатель команды');
    t.members.remove(userId);
    touch();
  }

  void updateNow({String? name, bool? isOpen}) {
    final t = myTeam;
    if (t == null || t.ownerId != me) throw const SocialError('Это может только создатель команды');
    if (name != null && name.trim().length >= 3) t.name = name.trim();
    if (isOpen != null) t.isOpen = isOpen;
    touch();
  }

  // --- the fake server's answers for teams (the app's MyTeamOut and OpenTeamOut) --------------

  Map<String, Object?> teamStateJson() {
    final t = myTeam;
    final ends = DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String();
    Map<String, Object?> goal(String id, String scope, String metric, int target, int pct) => {
          'id': id, 'scope': scope, 'metric': metric, 'target': target, 'progress': target * pct ~/ 100, 'xp': scope == 'season' ? 200 : 60,
          'reward': {'type': 'chest', 'amount': 1, 'key': scope == 'season' ? 'gold' : 'wood'}, 'claimed': false, 'claimable': false,
        };
    return {
      'team': t == null
          ? null
          : {
              'id': t.id, 'name': t.name, 'is_open': t.isOpen, 'is_owner': t.ownerId == me,
              'members': [
                for (final id in t.members)
                  {'user_id': id, 'login': id == me ? 'Demo' : nameOf(id), 'avatar_url': null, 'is_owner': id == t.ownerId, 'week_xp': id == me ? 120 : 40 + id % 7 * 30, 'badge': null},
              ],
              'week': {'ends_at': ends, 'goals': [goal('w1', 'week', 'word', 150, 48), goal('w2', 'week', 'lesson', 20, 35)]},
              'season_goal': goal('s1', 'season', 'streak', 300, t.seasonGoal),
            },
      'invites': <Object>[],
      'capacity': capacity,
    };
  }

  List<Map<String, Object?>> openTeamsJson() => [
        for (final t in teams.values)
          if (t.isOpen && roomIn(t) > 0 && !t.members.contains(me)) {'id': t.id, 'name': t.name, 'members': t.members.length, 'capacity': capacity},
      ];
}
