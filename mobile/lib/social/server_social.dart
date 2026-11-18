// The social data from the real server: the feed, friend requests, other people, team requests.
// Changes show at once (the heart, a request sent) and are told to the server; when the server
// refuses, the change is taken back and the words of the refusal are shown.

import 'dart:async';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/team.dart' as model;
import 'social_store.dart';

const _weekdays = ['понедельник', 'вторник', 'среда', 'четверг', 'пятница', 'суббота', 'воскресенье'];

class ServerSocial extends SocialStore {
  ServerSocial();

  int _me = 0;
  @override
  int get me => _me;

  int _capacity = 5;
  @override
  int get capacity => _capacity;

  List<String> _phrases = const ['Молодец!', 'Так держать!', 'Огонь!', 'Горжусь тобой', 'Догоню тебя', 'Вместе к цели'];
  @override
  List<String> get phrases => _phrases;

  int? _wordsToday;
  int? _goal;
  @override
  int? get wordsToday => _wordsToday;
  @override
  int? get dailyGoal => _goal;

  @override
  bool get realAvatars => true;
  @override
  String? get myAvatarUrl => _api.cachedMyProfile()?.avatarUrl;
  @override
  String get myLogin => _api.cachedMyProfile()?.login ?? '';

  ApiClient get _api => ApiClient.instance;
  int _offset = 0;
  bool _refreshing = false;

  // --- reading the server's shapes ------------------------------------------------------------

  SocialPerson _person(Map<String, dynamic> j) {
    final id = j['user_id'] as int;
    final old = people[id];
    final p = SocialPerson(
      id,
      (j['login'] as String?) ?? old?.name ?? '?',
      id % 7,
      old?.rank ?? '',
      old?.points ?? 0,
      old?.achievements ?? 0,
      old?.week ?? const [0, 0, 0, 0, 0, 0, 0],
      hours: old?.hours ?? '',
      bestDay: old?.bestDay ?? '',
      accuracy: old?.accuracy ?? 0,
      avgAnswer: old?.avgAnswer ?? '',
      achievementsTotal: old?.achievementsTotal ?? 0,
      avatarUrl: (j['avatar_url'] as String?) ?? old?.avatarUrl,
      real: true,
      premium: (j['is_premium'] as bool?) ?? old?.premium ?? false,
      studying: old?.studying ?? '',
    );
    people[id] = p;
    return p;
  }

  static String _ago(DateTime at) {
    final d = DateTime.now().difference(at.toLocal());
    if (d.inMinutes < 2) return tr('только что');
    if (d.inMinutes < 60) return tr('{0} мин назад', [d.inMinutes]);
    if (d.inHours < 24) return tr('{0} ч назад', [d.inHours]);
    if (d.inHours < 48) return tr('вчера');
    return tr('{0} дн. назад', [d.inDays]);
  }

  SocialCard _card(Map<String, dynamic> j) {
    final author = _person(j['person'] as Map<String, dynamic>);
    if (j['is_friend'] == true && author.id != _me) friends.add(author.id);
    for (final l in (j['likers'] as List<dynamic>)) {
      _person(l as Map<String, dynamic>);
    }
    final data = (j['data'] as Map<String, dynamic>?) ?? const {};
    final kind = j['kind'] as String;
    final liked = j['liked'] as bool;
    final mine = j['my_comment'] as String?;
    String title;
    String sub;
    switch (kind) {
      case 'streak':
        title = tr('{0} дней подряд', [data['days']]);
        sub = tr('Серия');
      case 'words':
        title = tr('Выучил(а) сегодня {0} слов', [data['count']]);
        sub = tr('Обновляется в течение дня');
      case 'achievement':
        title = tr('Новое достижение');
        sub = '${data['title'] ?? ''}';
      case 'duel':
        title = tr('Победа в дуэли недели');
        sub = tr('{0} против {1}', [data['mine'], data['theirs']]);
      case 'rank':
        title = tr('Новый ранг: {0}', [data['rank']]);
        sub = tr('Рейтинг');
      default:
        title = '';
        sub = '';
    }
    final last = j['last_comment'] as Map<String, dynamic>?;
    int? lastBy;
    if (last != null) {
      lastBy = _person(last['person'] as Map<String, dynamic>).id;
    }
    final likers = [
      for (final l in (j['likers'] as List<dynamic>)) if ((l as Map<String, dynamic>)['user_id'] != _me) l['user_id'] as int,
    ];
    final card = SocialCard(
      j['id'] as int,
      author.id,
      kind,
      title,
      sub,
      _ago(DateTime.parse(((kind == 'words' ? j['updated_at'] : j['created_at']) as String)).toUtc()),
      (j['likes'] as int) - (liked ? 1 : 0),
      (j['comments'] as int) - (mine != null ? 1 : 0),
      likers,
      last == null || lastBy == null || lastBy == _me ? null : (lastBy, last['phrase'] as String),
      views: j['views'] as int?,
    )
      ..liked = liked
      ..myComment = mine;
    return card;
  }

  void _readTeam(Map<String, dynamic> j) {
    final members = [
      for (final m in (j['members'] as List<dynamic>))
        () {
          final mj = m as Map<String, dynamic>;
          _person({...mj});
          return mj['user_id'] as int;
        }(),
    ];
    final id = j['id'] as int;
    final old = teams[id];
    teams[id] = SocialTeam(id, j['name'] as String, j['is_open'] as bool, (j['owner_id'] as int?) ?? old?.ownerId ?? 0, members, (j['season_percent'] as int?) ?? old?.seasonGoal ?? 0);
    if (j['requested'] == true) teamRequests.add(id);
    if (j['requested'] == false) teamRequests.remove(id);
  }

  // --- loading --------------------------------------------------------------------------------

  Future<void> _loadMe() async {
    if (_me != 0) return;
    try {
      _me = (await _api.fetchMyProfile()).id;
    } catch (_) {
      _me = _api.cachedMyProfile()?.id ?? 0;
    }
    final g = _api.cachedDailyGoal();
    _wordsToday = g?.done;
    _goal = g?.goal;
  }

  @override
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    loading = cards.isEmpty;
    touch();
    try {
      await _loadMe();
      final results = await Future.wait<dynamic>([
        _api.socialCall('GET', '/feed'),
        _api.socialCall('GET', '/friends/requests'),
        _api.socialCall('GET', '/teams/open?closed=true'),
        _api.socialCall('GET', '/teams/me'),
        _api.fetchDailyGoal(),
      ]);
      final feed = results[0] as Map<String, dynamic>;
      cards
        ..clear()
        ..addAll([for (final c in (feed['cards'] as List<dynamic>)) _card(c as Map<String, dynamic>)]);
      hasMore = feed['has_more'] as bool;
      _offset = cards.length;
      _phrases = [for (final p in (feed['phrases'] as List<dynamic>)) p as String];
      suggestions = [
        for (final s in ((feed['suggestions'] as List<dynamic>?) ?? const []))
          () {
            final sj = s as Map<String, dynamic>;
            final p = _person(sj);
            return (p.id, sj['reason'] == 'mutual' ? tr('Общих друзей: {0}', [sj['count']]) : tr('Занимается рядом с вами'));
          }(),
      ];
      final asks = results[1] as Map<String, dynamic>;
      friendRequests
        ..clear()
        ..addAll([for (final p in (asks['outgoing'] as List<dynamic>)) _person(p as Map<String, dynamic>).id]);
      incomingRequests
        ..clear()
        ..addAll([for (final p in (asks['incoming'] as List<dynamic>)) _person(p as Map<String, dynamic>).id]);
      teams.clear();
      for (final t in (results[2] as List<dynamic>)) {
        final tj = t as Map<String, dynamic>;
        final id = tj['id'] as int;
        teams[id] = SocialTeam(id, tj['name'] as String, tj['is_open'] as bool, 0, [], 0, memberCount: tj['members'] as int);
        if (tj['requested'] == true) teamRequests.add(id);
      }
      final mine = results[3] as Map<String, dynamic>;
      _capacity = (mine['capacity'] as int?) ?? 5;
      teamRequests
        ..clear()
        ..addAll([for (final r in ((mine['my_requests'] as List<dynamic>?) ?? const [])) r as int]);
      teamAskers
        ..clear()
        ..addAll([for (final r in ((mine['requests'] as List<dynamic>?) ?? const [])) _person(r as Map<String, dynamic>).id]);
      final team = mine['team'] as Map<String, dynamic>?;
      if (team != null) {
        final t = model.Team.fromJson(team);
        teams[t.id] = SocialTeam(t.id, t.name, t.isOpen, t.members.firstWhere((m) => m.isOwner, orElse: () => t.members.first).userId, [for (final m in t.members) m.userId], 0);
        for (final m in t.members) {
          _person({'user_id': m.userId, 'login': m.login, 'avatar_url': m.avatarUrl});
        }
      }
      final goal = results[4];
      if (goal != null) {
        _wordsToday = (goal as dynamic).done as int;
        _goal = goal.goal as int;
      }
    } finally {
      _refreshing = false;
      loading = false;
      touch();
    }
  }

  @override
  Future<void> more() async {
    if (!hasMore) return;
    final feed = await _api.socialCall('GET', '/feed?offset=$_offset') as Map<String, dynamic>;
    final seen = {for (final c in cards) c.id};
    for (final c in (feed['cards'] as List<dynamic>)) {
      final card = _card(c as Map<String, dynamic>);
      if (seen.add(card.id)) cards.add(card);
    }
    hasMore = feed['has_more'] as bool;
    _offset += (feed['cards'] as List<dynamic>).length;
    touch();
  }

  @override
  Future<void> ensurePerson(int id) async {
    final j = await _api.socialCall('GET', '/people/$id') as Map<String, dynamic>;
    final habits = (j['habits'] as Map<String, dynamic>?) ?? const {};
    final old = people[id];
    people[id] = SocialPerson(
      id,
      j['login'] as String,
      id % 7,
      (j['rank'] as String?) ?? '',
      (j['total_points'] as int?) ?? 0,
      (j['achievements_earned'] as int?) ?? 0,
      [for (final v in (j['week_points'] as List<dynamic>)) v as int],
      hours: (habits['hours'] as String?) ?? '',
      bestDay: habits['best_day'] == null ? '' : _weekdays[habits['best_day'] as int],
      accuracy: (habits['accuracy'] as int?) ?? 0,
      avgAnswer: habits['avg_answer'] == null ? '' : '${habits['avg_answer']}'.replaceAll('.', ','),
      achievementsTotal: (j['achievements_total'] as int?) ?? 0,
      avatarUrl: (j['avatar_url'] as String?) ?? old?.avatarUrl,
      real: true,
      premium: (j['is_premium'] as bool?) ?? false,
      studying: ((j['studying'] as List<dynamic>?) ?? const []).join(', '),
    );
    switch (j['relation']) {
      case 'friend':
        friends.add(id);
        friendRequests.remove(id);
      case 'sent':
        friends.remove(id);
        friendRequests.add(id);
      default:
        friends.remove(id);
        friendRequests.remove(id);
    }
    final t = j['team'] as Map<String, dynamic>?;
    if (t != null) {
      final tid = t['id'] as int;
      final known = teams[tid];
      teams[tid] = SocialTeam(tid, t['name'] as String, t['is_open'] as bool, known?.ownerId ?? 0, [...?known?.members, if (known == null || !known.members.contains(id)) id], known?.seasonGoal ?? 0, memberCount: t['members'] as int);
      if (t['requested'] == true) teamRequests.add(tid);
    }
    touch();
  }

  @override
  Future<void> ensureTeam(int id) async {
    _readTeam(await _api.socialCall('GET', '/teams/$id') as Map<String, dynamic>);
    touch();
  }

  @override
  Future<void> loadLikers(SocialCard c) async {
    final list = await _api.socialCall('GET', '/feed/${c.id}/likers') as List<dynamic>;
    final ids = <int>[];
    for (final p in list) {
      final pj = p as Map<String, dynamic>;
      final id = _person(pj).id;
      switch (pj['relation']) {
        case 'friend':
          friends.add(id);
        case 'sent':
          friendRequests.add(id);
      }
      if (id != _me) ids.add(id);
    }
    c.likers
      ..clear()
      ..addAll(ids);
    c.likes = ids.length;
    touch();
  }

  // --- reactions ------------------------------------------------------------------------------

  Future<T> _try<T>(Future<T> Function() call, void Function() undo) async {
    try {
      return await call();
    } on ApiException catch (e) {
      undo();
      touch();
      throw SocialError(e.message);
    } catch (_) {
      undo();
      touch();
      throw SocialError(tr('Не удалось. Проверьте интернет.'));
    }
  }

  @override
  Future<void> toggleLike(SocialCard c) async {
    final on = !c.liked;
    c.liked = on;
    touch();
    await _try(() => _api.socialCall(on ? 'POST' : 'DELETE', '/feed/${c.id}/like'), () => c.liked = !on);
  }

  @override
  Future<void> setComment(SocialCard c, String phrase) async {
    final before = c.myComment;
    c.myComment = phrase;
    touch();
    await _try(() => _api.socialCall('POST', '/feed/${c.id}/comment', body: {'phrase': phrase}), () => c.myComment = before);
  }

  @override
  Future<void> hide(SocialCard c) async {
    hiddenCards.add(c.id);
    touch();
    await _try(() => _api.socialCall('POST', '/feed/${c.id}/hide'), () => hiddenCards.remove(c.id));
  }

  // --- friends --------------------------------------------------------------------------------

  @override
  Future<void> toggleFriendRequest(int id) async {
    final waiting = friendRequests.contains(id);
    if (waiting) {
      friendRequests.remove(id);
    } else {
      friendRequests.add(id);
    }
    touch();
    final answer = await _try<dynamic>(
      () => waiting ? _api.socialCall('DELETE', '/friends/requests/$id') : _api.socialCall('POST', '/friends/requests', body: {'user_id': id}),
      () => waiting ? friendRequests.add(id) : friendRequests.remove(id),
    );
    // They had asked first: now friends at once.
    if (answer is Map<String, dynamic> && answer['relation'] == 'friend') {
      friendRequests.remove(id);
      friends.add(id);
      touch();
    }
  }

  @override
  Future<void> removeFriend(int id) async {
    friends.remove(id);
    touch();
    await _try(() => _api.socialCall('DELETE', '/friends/$id'), () => friends.add(id));
  }

  @override
  Future<void> answerFriendRequest(int id, {required bool accept}) async {
    incomingRequests.remove(id);
    touch();
    await _try(() => _api.socialCall('POST', '/friends/requests/$id/${accept ? 'accept' : 'decline'}'), () => incomingRequests.add(id));
    if (accept) friends.add(id);
    touch();
  }

  @override
  Future<void> answerTeamRequest(int userId, {required bool accept}) async {
    teamAskers.remove(userId);
    touch();
    await _try(() => _api.socialCall('POST', '/teams/me/requests/$userId/${accept ? 'accept' : 'decline'}'), () => teamAskers.add(userId));
    if (accept) await refresh();
  }

  // --- teams ----------------------------------------------------------------------------------

  @override
  Future<void> join(int teamId) async {
    await _try(() => _api.socialCall('POST', '/teams/$teamId/join'), () {});
    await refresh();
    await ensureTeam(teamId);
  }

  @override
  Future<void> toggleTeamRequest(int teamId) async {
    final asked = teamRequests.contains(teamId);
    if (asked) {
      teamRequests.remove(teamId);
    } else {
      teamRequests.add(teamId);
    }
    touch();
    await _try(
      () => asked ? _api.socialCall('DELETE', '/teams/$teamId/request') : _api.socialCall('POST', '/teams/$teamId/request'),
      () => asked ? teamRequests.add(teamId) : teamRequests.remove(teamId),
    );
  }

  @override
  Future<SocialTeam> create(String name, {required bool isOpen}) async {
    final state = await _try(() => _api.createTeam(name, isOpen: isOpen), () {});
    await refresh();
    return teams[state.team!.id]!;
  }

  @override
  Future<void> leave() async {
    await _try(() => _api.leaveTeam(), () {});
    await refresh();
  }
}
