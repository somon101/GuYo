// What the «Лента», the profile of another person and the team sheets work on: people, cards, friends,
// requests and teams, kept in memory and announced through [changes]. The screens never talk to the
// server themselves: the app fills this from the server (server_social.dart), the demo build from
// made-up data (demo/demo_social.dart).

import 'package:flutter/foundation.dart';

import '../l10n/l10n.dart';

/// Somebody else (never the player: the player is [SocialStore.me]).
class SocialPerson {
  final int id;
  final String name;
  final int color; // index into the avatar colours (the letter avatar of the demo)
  final String rank;
  final int points;
  final int achievements; // earned
  final int achievementsTotal;
  final List<int> week; // points Monday..Sunday (oldest..today for the server)
  final String hours; // when they usually study
  final String bestDay;
  final int accuracy;
  final String avgAnswer; // seconds per answer, as shown
  /// The finished picture of the avatar (the server); null in the demo and for a default avatar.
  final String? avatarUrl;

  /// True for a person that came from the server (their avatar is drawn by the app's own widget).
  final bool real;
  final bool premium;
  final String studying;
  const SocialPerson(this.id, this.name, this.color, this.rank, this.points, this.achievements, this.week,
      {this.hours = '19–21 ч',
      this.bestDay = 'вторник',
      this.accuracy = 88,
      this.avgAnswer = '3,1',
      this.achievementsTotal = 20,
      this.avatarUrl,
      this.real = false,
      this.premium = true,
      this.studying = ''});
}

/// One card of the feed: something good that happened to someone.
class SocialCard {
  final int id;
  final int personId;
  final String icon; // streak | words | gem | rank | duel | achievement
  final String title;
  final String subtitle;
  final String when;
  int likes; // from others
  int comments; // from others
  final List<int> likers; // those who liked, newest first (without the player)
  (int, String)? lastComment;
  bool liked = false;
  String? myComment;

  /// Only for the author's own cards: how many people saw it.
  final int? views;
  SocialCard(this.id, this.personId, this.icon, this.title, this.subtitle, this.when, this.likes, this.comments, this.likers, this.lastComment, {this.views});

  int get likeCount => likes + (liked ? 1 : 0);
  int get commentCount => comments + (myComment != null ? 1 : 0);
}

class SocialTeam {
  final int id;
  String name;
  bool isOpen;
  int ownerId;
  final List<int> members;
  int seasonGoal; // percent done

  /// How many people are in it when the members themselves are not known (a search result).
  int? memberCount;
  SocialTeam(this.id, this.name, this.isOpen, this.ownerId, this.members, this.seasonGoal, {this.memberCount});

  int get count => memberCount ?? members.length;
}

/// A rule a team or friend action broke, with the words to show.
class SocialError implements Exception {
  final String message;
  const SocialError(this.message);
  @override
  String toString() => message;
}

abstract class SocialStore {
  /// The store the screens use; set once when the app starts.
  static late SocialStore instance;

  /// The player's own id.
  int get me;
  int get capacity => 5;

  /// Ready-made comments: nobody types their own.
  List<String> get phrases => const ['Молодец!', 'Так держать!', 'Огонь!', 'Горжусь тобой', 'Догоню тебя', 'Вместе к цели'];

  final Map<int, SocialPerson> people = {};
  final Set<int> friends = {};

  /// Friend requests the player has sent and that are not answered yet.
  final Set<int> friendRequests = {};

  /// People who asked the player to be friends and wait for an answer.
  final List<int> incomingRequests = [];

  /// Teams the player has asked to join (closed teams: the owner decides).
  final Set<int> teamRequests = {};

  /// Why someone is suggested in «Возможно, вы знакомы» (person id, the reason as text).
  List<(int, String)> suggestions = [];
  final List<SocialCard> cards = [];
  final Map<int, SocialTeam> teams = {};
  final Set<int> hiddenCards = {};

  /// Bumped on every change, so every screen showing friends or teams redraws at once.
  final ValueNotifier<int> changes = ValueNotifier(0);
  void touch() => changes.value++;

  /// True while the first load is under way (the feed shows a quiet placeholder).
  bool loading = false;
  bool hasMore = false;

  /// What the feed's «Ваша очередь» card shows (null: the card is left out).
  int? get wordsToday => null;
  int? get dailyGoal => null;

  /// «Сегодня в GuYo выучено …» (null: the card is left out; only the demo has made-up numbers).
  String? get globalWordsToday => null;

  String nameOf(int id) => id == me ? tr('Вы') : people[id]?.name ?? '?';

  /// True when avatars are the app's own pictures (the server); the demo draws coloured letters.
  bool get realAvatars => false;
  String? get myAvatarUrl => null;
  String get myLogin => '';

  bool isFriend(int id) => friends.contains(id);

  SocialTeam? teamOf(int personId) {
    for (final t in teams.values) {
      if (t.members.contains(personId)) return t;
    }
    return null;
  }

  SocialTeam? get myTeam => teamOf(me);

  int roomIn(SocialTeam t) => capacity - t.count;

  // --- loading -------------------------------------------------------------------------------

  /// Loads (or reloads) the feed, the suggestions and the teams that look for people.
  Future<void> refresh() async {}

  /// The next page of the feed.
  Future<void> more() async {}

  /// Makes sure the full profile of this person is loaded.
  Future<void> ensurePerson(int id) async {}

  /// Makes sure this team is loaded with its members.
  Future<void> ensureTeam(int id) async {}

  /// Loads the whole list of those who liked a card.
  Future<void> loadLikers(SocialCard c) async {}

  // --- reactions ------------------------------------------------------------------------------

  Future<void> toggleLike(SocialCard c);
  Future<void> setComment(SocialCard c, String phrase);
  Future<void> hide(SocialCard c);

  // --- friends --------------------------------------------------------------------------------

  /// Sends a friend request, or takes it back when one is already waiting.
  Future<void> toggleFriendRequest(int id);
  Future<void> removeFriend(int id);

  /// Answers a request somebody sent to the player.
  Future<void> answerFriendRequest(int id, {required bool accept}) async => incomingRequests.remove(id);

  /// Whom the creator of the player's team has waiting (people asking to join).
  final List<int> teamAskers = [];
  Future<void> answerTeamRequest(int userId, {required bool accept}) async => teamAskers.remove(userId);

  // --- teams ----------------------------------------------------------------------------------

  /// Joins an open team with room at once.
  Future<void> join(int teamId);

  /// Asks a closed team to take the player, or takes the request back.
  Future<void> toggleTeamRequest(int teamId);
  Future<SocialTeam> create(String name, {required bool isOpen});
  Future<void> leave();
}
