// The demo's people, feed cards, friends and teams. One place, used both by the demo's own screens
// (demo_feed.dart) and by the fake server's team answers, so what the season pass shows under
// «Командные цели» and what the feed shows are the same teams. Nothing here is used by the real app.

import 'package:flutter/foundation.dart';

/// Somebody in the demo (never the player: the player is [DemoSocial.me]).
class DemoPerson {
  final int id;
  final String name;
  final int color; // index into the avatar colours
  final String rank;
  final int points;
  final int achievements; // earned, out of 20
  final List<int> week; // points Monday..Sunday
  final String hours; // when they usually study
  final String bestDay;
  final int accuracy;
  final String avgAnswer; // seconds per answer, as shown
  const DemoPerson(this.id, this.name, this.color, this.rank, this.points, this.achievements, this.week,
      {this.hours = '19–21 ч', this.bestDay = 'вторник', this.accuracy = 88, this.avgAnswer = '3,1'});
}

/// One card of the feed: something good that happened to someone.
class DemoCard {
  final int id;
  final int personId;
  final String icon; // streak | words | gem | rank | duel
  final String title;
  final String subtitle;
  final String when;
  final int likes; // from others
  final int comments;
  final List<int> likers; // the first few who liked it, newest first
  final (int, String) lastComment;
  bool liked = false;
  String? myComment;
  DemoCard(this.id, this.personId, this.icon, this.title, this.subtitle, this.when, this.likes, this.comments, this.likers, this.lastComment);

  int get likeCount => likes + (liked ? 1 : 0);
  int get commentCount => comments + (myComment != null ? 1 : 0);
}

class DemoTeam {
  final int id;
  String name;
  bool isOpen;
  int ownerId;
  final List<int> members;
  final int seasonGoal; // percent done
  DemoTeam(this.id, this.name, this.isOpen, this.ownerId, this.members, this.seasonGoal);
}

/// A rule a team action broke, with the words to show (the fake server answers it as an error).
class DemoTeamError implements Exception {
  final String message;
  const DemoTeamError(this.message);
  @override
  String toString() => message;
}

class DemoSocial {
  DemoSocial._();
  static final DemoSocial instance = DemoSocial._();

  /// The player's id inside teams (the same as /users/me).
  static const int me = 1;
  static const int capacity = 5;

  /// Ready-made comments: nobody types their own.
  static const List<String> phrases = ['Молодец!', 'Так держать!', 'Огонь!', 'Горжусь тобой', 'Догоню тебя', 'Вместе к цели'];

  final Map<int, DemoPerson> people = {
    for (final p in const [
      DemoPerson(101, 'Aziz', 0, 'Мастер', 1840, 9, [60, 90, 40, 120, 30, 80, 70], bestDay: 'четверг', accuracy: 92),
      DemoPerson(102, 'Madina', 1, 'Знаток', 1620, 7, [40, 85, 60, 120, 0, 95, 70], accuracy: 91),
      DemoPerson(103, 'Rustam', 2, 'Знаток', 1500, 5, [20, 40, 75, 60, 90, 10, 50], hours: '7–9 ч', bestDay: 'пятница'),
      DemoPerson(104, 'Nilufar', 5, 'Ученик', 1410, 2, [30, 0, 45, 20, 60, 35, 0], hours: '12–14 ч'),
      DemoPerson(105, 'Jasur', 4, 'Ученик', 1330, 4, [80, 70, 0, 55, 40, 100, 20], bestDay: 'суббота'),
      DemoPerson(106, 'Zarina', 3, 'Мастер', 1290, 11, [100, 60, 80, 110, 70, 0, 90], hours: '21–23 ч', accuracy: 94),
      DemoPerson(108, 'Sardor', 2, 'Ученик', 1100, 3, [10, 30, 40, 0, 50, 20, 30]),
      DemoPerson(109, 'Malika', 3, 'Знаток', 980, 3, [50, 20, 0, 40, 30, 60, 10], hours: '18–20 ч'),
      DemoPerson(110, 'Farrukh', 4, 'Ученик', 1210, 4, [40, 40, 50, 30, 20, 0, 60]),
      DemoPerson(111, 'Dilnoza', 5, 'Новичок', 430, 1, [0, 20, 10, 30, 0, 15, 25]),
      DemoPerson(112, 'Bekzod', 0, 'Ученик', 760, 2, [20, 30, 0, 25, 40, 10, 0]),
      DemoPerson(113, 'Shahlo', 1, 'Знаток', 1520, 12, [90, 80, 70, 100, 60, 80, 110], accuracy: 95),
    ])
      p.id: p,
  };

  /// Friends of the player (mutual, as in the app).
  final Set<int> friends = {101, 102};

  /// Friend requests the player has sent and that are not answered yet.
  final Set<int> friendRequests = {};

  /// Teams the player has asked to join (closed teams: the owner decides).
  final Set<int> teamRequests = {};

  /// Why someone is suggested in «Возможно, вы знакомы».
  final List<(int, String)> suggestions = const [
    (108, '3 общих друга'),
    (109, 'Друг Aziz'),
    (110, 'Ваш ранг, занимается каждый день'),
    (111, 'Учит те же темы'),
  ];

  late final List<DemoCard> cards = [
    DemoCard(1, 101, 'streak', '7 дней подряд', 'Серия', 'только что', 20, 3, [102, 103, 108, 109, 110, 111, 112, 113], (102, 'Молодец!')),
    DemoCard(2, 102, 'words', 'Выучила сегодня 12 слов', 'Обновляется в течение дня', 'сегодня', 7, 1, [101, 106, 105, 104, 108, 109, 110], (101, 'Так держать!')),
    DemoCard(3, 103, 'gem', '100 слов выучено', 'Достижение «Начитанный»', '2 ч назад', 354, 20, [106, 113, 101, 112, 109, 111, 110, 105], (106, 'Огонь!')),
    DemoCard(4, 106, 'rank', 'Новый ранг: Мастер', 'Рейтинг', '5 ч назад', 2099, 126, [105, 102, 103, 113, 108, 104, 112, 110], (105, 'Горжусь тобой')),
    DemoCard(5, 105, 'duel', 'Победа в дуэли недели', '328 против 290', 'вчера', 61, 5, [104, 101, 111, 109, 108, 113], (104, 'Молодец!')),
    DemoCard(6, 104, 'streak', '3 дня подряд', 'Первая серия', 'вчера', 36, 4, [103, 102, 112, 110, 106, 109], (103, 'Так держать!')),
  ];

  final Map<int, DemoTeam> teams = {
    1: DemoTeam(1, 'Словарный взвод', true, 101, [101, 108, 109], 62),
    2: DemoTeam(2, 'Ночные совы', false, 106, [106, 105, 113, 112], 80),
    3: DemoTeam(3, 'Утренний урок', false, 102, [102, 103, 111, 110], 71),
    4: DemoTeam(4, 'Без выходных', true, 104, [104, 112, 110, 111, 113], 93),
  };
  int _nextTeamId = 10;

  /// Bumped on every change, so every screen showing friends or teams redraws at once.
  final ValueNotifier<int> changes = ValueNotifier(0);
  void touch() => changes.value++;

  /// Cards the player chose to hide.
  final Set<int> hiddenCards = {};

  String nameOf(int id) => id == me ? 'Вы' : people[id]?.name ?? '?';

  // --- friends -------------------------------------------------------------------------------

  bool isFriend(int id) => friends.contains(id);

  /// Sends a friend request, or takes it back when one is already waiting.
  void toggleFriendRequest(int id) {
    if (!friendRequests.remove(id)) friendRequests.add(id);
    touch();
  }

  void removeFriend(int id) {
    friends.remove(id);
    touch();
  }

  // --- teams ---------------------------------------------------------------------------------

  DemoTeam? teamOf(int personId) {
    for (final t in teams.values) {
      if (t.members.contains(personId)) return t;
    }
    return null;
  }

  DemoTeam? get myTeam => teamOf(me);

  int roomIn(DemoTeam t) => capacity - t.members.length;

  /// Joins an open team with room at once.
  void join(int teamId) {
    final t = teams[teamId];
    if (t == null || !t.isOpen) throw const DemoTeamError('Эта команда закрыта для вступления');
    if (myTeam != null) throw const DemoTeamError('Вы уже состоите в команде');
    if (roomIn(t) <= 0) throw const DemoTeamError('В команде нет мест');
    t.members.add(me);
    teamRequests.remove(teamId);
    touch();
  }

  /// Asks a closed team to take the player, or takes the request back.
  void toggleTeamRequest(int teamId) {
    if (!teamRequests.remove(teamId)) teamRequests.add(teamId);
    touch();
  }

  DemoTeam create(String name, {required bool isOpen}) {
    final n = name.trim();
    if (n.length < 3 || n.length > 24) throw const DemoTeamError('Название команды: от 3 до 24 символов');
    if (myTeam != null) throw const DemoTeamError('Вы уже состоите в команде');
    final t = DemoTeam(_nextTeamId++, n, isOpen, me, [me], 0);
    teams[t.id] = t;
    touch();
    return t;
  }

  void leave() {
    final t = myTeam;
    if (t == null) throw const DemoTeamError('Вы не состоите в команде');
    t.members.remove(me);
    if (t.members.isEmpty) {
      teams.remove(t.id);
    } else if (t.ownerId == me) {
      t.ownerId = t.members.first; // the longest-standing member
    }
    touch();
  }

  void kick(int userId) {
    final t = myTeam;
    if (t == null || t.ownerId != me) throw const DemoTeamError('Это может только создатель команды');
    t.members.remove(userId);
    touch();
  }

  void update({String? name, bool? isOpen}) {
    final t = myTeam;
    if (t == null || t.ownerId != me) throw const DemoTeamError('Это может только создатель команды');
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
