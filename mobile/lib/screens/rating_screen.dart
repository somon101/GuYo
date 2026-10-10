import '../l10n/l10n.dart';
import 'scan_friend_screen.dart';
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../services/session_cache.dart';
import '../models/user_rating.dart';
import '../widgets/leaderboard_status.dart';
import 'status_picker_sheet.dart';
import '../theme/app_colors.dart';
import '../widgets/position_change.dart';
import '../widgets/rank_icon.dart';
import '../widgets/user_avatar.dart';
import '../widgets/user_name.dart';
import 'all_ranks_screen.dart';
import '../widgets/skeleton.dart';

/// "Рейтинг" tab: shows only the leaderboard of the user's OWN current
/// rank -- there is no control anywhere on this screen to pick a
/// different one, by design (backend/app/routers/rating.py's
/// /rating/leaderboard always answers for the caller's own rank). Not
/// dictionary-scoped (rating is per-user, not per-language), same as
/// "Профиль".
///
/// The board is read top-down: the first three places are the podium, the
/// user's own rank is the card under it, and everyone from fourth place
/// onward is the compact list below. Nothing is shown twice -- the list
/// deliberately starts where the podium ends.
class RatingScreen extends StatefulWidget {
  const RatingScreen({super.key});

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

LeaderboardEntry? _myEntry(Leaderboard board) {
  for (final e in board.entries) {
    if (e.isMe) return e;
  }
  return null;
}

class _RatingScreenState extends State<RatingScreen> {
  bool _isLoading = true;
  String? _loadError;
  Leaderboard? _board;
  // Only needed to open the existing "Все уровни" ladder from the rank
  // card's chevron; the board itself never depends on it, so a failure
  // here just leaves the card unopenable rather than breaking the screen.
  UserRating? _rating;

  @override
  void initState() {
    super.initState();
    _board = SessionCache.get<Leaderboard>('rating-my-rank') ?? ApiClient.instance.cachedMyRankLeaderboard();
    _isLoading = _board == null;
    _load();
  }

  /// Opens the status picker; a saved status shows on the board at once.
  Future<void> _editStatus() async {
    final saved = await showStatusPicker(context);
    if (saved != null) _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = _board == null;
      _loadError = null;
    });
    try {
      final board = await ApiClient.instance.fetchMyRankLeaderboard();
      SessionCache.put('rating-my-rank', board);
      if (!mounted) return;
      setState(() {
        _board = board;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (_board == null) _loadError = tr('Не удалось загрузить рейтинг');
      });
    }
    _loadRating();
  }

  Future<void> _loadRating() async {
    try {
      final rating = await ApiClient.instance.fetchMyRating();
      if (!mounted) return;
      setState(() => _rating = rating);
    } catch (_) {
      // See the field's own note -- best effort.
    }
  }

  Future<void> _openGlobal() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GlobalLeaderboardScreen()));
  }

  void _openAllRanks() {
    final rating = _rating;
    if (rating == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AllRanksScreen(rating: rating)));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.canvas,
      child: SafeArea(
        child: RefreshIndicator(onRefresh: _load, child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const SkeletonList();
    }
    if (_loadError != null) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: Text(tr('Повторить'))),
              ],
            ),
          ),
        ],
      );
    }

    final board = _board!;
    final rank = board.rank;
    final color = rank != null ? parseHexColor(rank.color) : AppColors.primary;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        LeaderboardHeader(
          title: tr('Рейтинг'),
          onOpenGlobal: _openGlobal,
          onOpenFriends: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const GlobalLeaderboardScreen(friends: true)),
          ),
        ),
        if (rank == null)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppShapes.cardRadius),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Text(
                tr('Пока нет ранга — начните учить слова, чтобы попасть в рейтинг'),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.secondaryText),
              ),
            ),
          )
        else ...[
          if (board.entries.isNotEmpty) ...[
            const SizedBox(height: 4),
            LeaderboardPodium(entries: board.entries, onEditMyStatus: _editStatus),
          ],
          const SizedBox(height: 14),
          _RankCard(
            rank: rank,
            color: color,
            onTap: _rating == null ? null : _openAllRanks,
            myStatusEmojiUrl: _myEntry(board)?.statusEmojiUrl,
            onEditStatus: _editStatus,
          ),
          const SizedBox(height: 14),
          if (board.entries.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                tr('Пока никто не в этом ранге'),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.secondaryText),
              ),
            )
          else
            // Everyone the podium didn't already show. Every row in this
            // board shares the caller's own rank, so a per-row rank badge
            // would repeat the card above on every line.
            for (final entry in board.entries.skip(LeaderboardPodium.placeCount))
              LeaderboardRow(entry: entry, accentColor: color, onEditMyStatus: _editStatus),
        ],
      ],
    );
  }
}

/// "Рейтинг" + the one button on this screen. Shared with the global
/// board so both read the same way.
class LeaderboardHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onOpenGlobal;
  final VoidCallback? onOpenFriends;

  const LeaderboardHeader({super.key, required this.title, this.onOpenGlobal, this.onOpenFriends});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
          ),
        ),
        if (onOpenFriends != null) ...[
          Material(
            color: AppColors.surface,
            shape: const CircleBorder(),
            child: InkWell(
              key: const ValueKey('rating-friends'),
              customBorder: const CircleBorder(),
              onTap: onOpenFriends,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.cardBorder),
                  boxShadow: AppShapes.cardShadow,
                ),
                child: Tooltip(
                  message: tr('Друзья'),
                  child: Icon(Icons.group_rounded, size: 20, color: AppColors.primary),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (onOpenGlobal != null)
          Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppShapes.pillRadius),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppShapes.pillRadius),
              onTap: onOpenGlobal,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppShapes.pillRadius),
                  border: Border.all(color: AppColors.cardBorder),
                  boxShadow: AppShapes.cardShadow,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.public, size: 16, color: AppColors.primary),
                    SizedBox(width: 6),
                    Text(
                      tr('Глобальный рейтинг'),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The top three of a board: first place centred and largest with a crown,
/// second and third flanking it a step lower.
///
/// Renders only the places that actually exist -- a board with one or two
/// people shows one or two plinths rather than empty slots, and first
/// place stays in the middle either way.
class LeaderboardPodium extends StatelessWidget {
  /// How many entries the podium consumes; the list below starts after it.
  static const int placeCount = 3;

  final List<LeaderboardEntry> entries;

  /// Tapping your own place opens the status picker.
  final VoidCallback? onEditMyStatus;

  const LeaderboardPodium({super.key, required this.entries, this.onEditMyStatus});

  @override
  Widget build(BuildContext context) {
    final first = entries.isNotEmpty ? entries[0] : null;
    final second = entries.length > 1 ? entries[1] : null;
    final third = entries.length > 2 ? entries[2] : null;

    return Stack(
      alignment: Alignment.topCenter,
      children: [
        // One soft halo behind first place, and nothing else: the podium
        // has to read as three people, not as a lit background.
        Positioned(
          top: 8,
          child: Container(
            width: 190,
            height: 190,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [AppColors.primary.withValues(alpha: 0.10), AppColors.primary.withValues(alpha: 0.0)],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: _PodiumPlace(entry: second, place: 2, onEditMyStatus: onEditMyStatus)),
              Expanded(child: _PodiumPlace(entry: first, place: 1, onEditMyStatus: onEditMyStatus)),
              Expanded(child: _PodiumPlace(entry: third, place: 3, onEditMyStatus: onEditMyStatus)),
            ],
          ),
        ),
      ],
    );
  }
}

/// The medal colours, by place. Conventional rather than GuYo-violet on
/// purpose: gold/silver/bronze is what makes a podium readable at a
/// glance, and it is the only place on this screen that leaves the
/// palette.
const Map<int, Color> _placeColors = {
  1: Color(0xFFE3A008),
  2: Color(0xFF9AA3C7),
  3: Color(0xFFC97B3C),
};

class _PodiumPlace extends StatelessWidget {
  final LeaderboardEntry? entry;
  final int place;
  final VoidCallback? onEditMyStatus;

  const _PodiumPlace({required this.entry, required this.place, this.onEditMyStatus});

  @override
  Widget build(BuildContext context) {
    final person = entry;
    final isFirst = place == 1;
    final avatarSize = isFirst ? 92.0 : 66.0;
    final color = _placeColors[place]!;

    if (person == null) {
      // Keeps first place centred when there is nobody to either side.
      return SizedBox(height: isFirst ? 0 : 150);
    }

    final card = Padding(
      padding: EdgeInsets.only(bottom: isFirst ? 0 : 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Only first place is crowned; the others reserve no space at
          // all, which is what lifts the winner above them.
          SizedBox(height: isFirst ? 26 : 0, child: isFirst ? const _Crown(size: 26) : null),
          const SizedBox(height: 4),
          SizedBox(
            width: avatarSize,
            height: avatarSize + 12,
            child: Stack(
              alignment: Alignment.topCenter,
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: avatarSize,
                  height: avatarSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withValues(alpha: 0.55), width: isFirst ? 3 : 2),
                    boxShadow: [
                      BoxShadow(color: color.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 4)),
                    ],
                  ),
                  padding: EdgeInsets.all(isFirst ? 3 : 2),
                  child: UserAvatar(
                    avatarUrl: person.avatarUrl,
                    login: person.login,
                    size: avatarSize - (isFirst ? 12 : 8),
                  ),
                ),
                // How far this person moved in their rank, in the
                // avatar's top-right corner.
                Positioned(
                  top: 0,
                  right: -6,
                  child: PositionChangeBadge(change: person.positionChange, fontSize: 11, outlined: true),
                ),
                if (person.statusEmojiUrl != null)
                  Positioned(
                    left: -4,
                    bottom: isFirst ? 14 : 10,
                    child: StatusEmojiBadge(url: person.statusEmojiUrl!, size: isFirst ? 30 : 24),
                  ),
                Positioned(
                  bottom: 0,
                  child: Container(
                    width: isFirst ? 28 : 24,
                    height: isFirst ? 28 : 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.surface, width: 2.5),
                    ),
                    child: Text(
                      '$place',
                      style: TextStyle(
                        fontSize: isFirst ? 13 : 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          UserNameText(
            person.login,
            isPremium: person.isPremium,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isFirst ? 15 : 13,
              fontWeight: FontWeight.w800,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.stars_rounded, size: isFirst ? 15 : 13, color: AppColors.gold),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '${person.totalPoints}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isFirst ? 14 : 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.secondaryText,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (person.isMe && onEditMyStatus != null) {
      return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onEditMyStatus, child: card);
    }
    return StatusBubble(emojiUrl: person.statusEmojiUrl, text: person.statusText, child: card);
  }
}

/// A small crown above first place.
///
/// Drawn rather than taken from an icon font: Material has no crown, and
/// an emoji would render differently on every device -- this is the one
/// shape the podium leans on, so it is worth owning.
class _Crown extends StatelessWidget {
  final double size;
  const _Crown({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 0.78,
      child: CustomPaint(painter: _CrownPainter(color: _placeColors[1]!)),
    );
  }
}

class _CrownPainter extends CustomPainter {
  final Color color;
  _CrownPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final body = Path()
      ..moveTo(0, h * 0.28)
      ..lineTo(w * 0.27, h * 0.62)
      ..lineTo(w * 0.5, h * 0.12)
      ..lineTo(w * 0.73, h * 0.62)
      ..lineTo(w, h * 0.28)
      ..lineTo(w * 0.86, h)
      ..lineTo(w * 0.14, h)
      ..close();
    canvas.drawPath(body, Paint()..color = color);

    // The three points, so the silhouette still reads as a crown at 26px.
    final stud = Paint()..color = color;
    canvas.drawCircle(Offset(0, h * 0.28), w * 0.1, stud);
    canvas.drawCircle(Offset(w * 0.5, h * 0.12), w * 0.11, stud);
    canvas.drawCircle(Offset(w, h * 0.28), w * 0.1, stud);
  }

  @override
  bool shouldRepaint(_CrownPainter oldDelegate) => oldDelegate.color != color;
}

/// The user's own rank, tinted by that rank's own colour. The chevron
/// opens the existing "Все уровни" ladder -- the same screen the Profile
/// already reaches, never a second one.
class _RankCard extends StatelessWidget {
  final RankSummary rank;
  final Color color;
  final VoidCallback? onTap;
  final String? myStatusEmojiUrl;
  final VoidCallback onEditStatus;

  const _RankCard({
    required this.rank,
    required this.color,
    required this.onTap,
    required this.myStatusEmojiUrl,
    required this.onEditStatus,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(AppShapes.cardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppShapes.cardRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppShapes.cardRadius),
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: Row(
            children: [
              RankIcon(rank: rank, color: color, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      rank.name,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tr('Топ-100 «{0}»', [rank.name]),
                      style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _StatusChip(emojiUrl: myStatusEmojiUrl, onTap: onEditStatus),
              if (onTap != null) Icon(Icons.chevron_right, color: color.withValues(alpha: 0.8)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line of the compact list: place, avatar, name, points.
///
/// [showRank] adds the row's own rank badge. Off on an own-rank board,
/// where every row shares the rank already named in the card above; on
/// for the global board, where the rank is the one thing that differs
/// from row to row.
class LeaderboardRow extends StatelessWidget {
  final LeaderboardEntry entry;
  final Color accentColor;
  final bool showRank;

  /// Tapping your own row opens the status picker; tapping anyone else's
  /// shows their status.
  final VoidCallback? onEditMyStatus;

  const LeaderboardRow({
    super.key,
    required this.entry,
    required this.accentColor,
    this.showRank = false,
    this.onEditMyStatus,
  });

  @override
  Widget build(BuildContext context) {
    final rowRank = entry.rank;
    final rowColor = rowRank != null ? parseHexColor(rowRank.color) : accentColor;
    final row = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: entry.isMe ? AppColors.primary.withValues(alpha: 0.07) : AppColors.surface,
          borderRadius: BorderRadius.circular(AppShapes.rowRadius),
          border: Border.all(
            color: entry.isMe ? AppColors.primary.withValues(alpha: 0.35) : AppColors.cardBorder,
          ),
          boxShadow: AppShapes.cardShadow,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text(
                '${entry.position}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.secondaryText),
              ),
            ),
            const SizedBox(width: 6),
            AvatarWithStatus(
              emojiUrl: entry.statusEmojiUrl,
              badgeSize: 19,
              child: UserAvatar(avatarUrl: entry.avatarUrl, login: entry.login, size: 36),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: UserNameText(
                        entry.login,
                        isPremium: entry.isPremium,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: entry.isMe ? FontWeight.w800 : FontWeight.w600,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ),
                    if (entry.statusText != null) const StatusPhraseHint(),
                  ],
                ),
              ),
            ),
            if ((entry.positionChange ?? 0) != 0) ...[
              PositionChangeBadge(change: entry.positionChange),
              const SizedBox(width: 8),
            ],
            if (showRank && rowRank != null) ...[
              RankIcon(rank: rowRank, color: rowColor, size: 22),
              const SizedBox(width: 8),
            ],
            Text(
              '${entry.totalPoints}',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.pointsOnSurface),
            ),
          ],
        ),
      ),
    );
    if (entry.isMe && onEditMyStatus != null) {
      return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onEditMyStatus, child: row);
    }
    return StatusBubble(emojiUrl: entry.statusEmojiUrl, text: entry.statusText, child: row);
  }
}

/// The small "Статус" button on the rank card: your emoji, or a plus
/// when you have none yet.
class _StatusChip extends StatelessWidget {
  final String? emojiUrl;
  final VoidCallback onTap;
  const _StatusChip({required this.emojiUrl, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('rating-status-chip'),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.fromLTRB(6, 5, 12, 5),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), boxShadow: AppShapes.cardShadow),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            emojiUrl != null
                ? StatusEmojiBadge(url: emojiUrl!, size: 24)
                : Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(color: AppColors.violetSurface, shape: BoxShape.circle),
                    child: Icon(Icons.add_rounded, size: 18, color: AppColors.primary),
                  ),
            const SizedBox(width: 6),
            Text(tr('Статус'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
          ],
        ),
      ),
    );
  }
}

/// The global top-100 -- entered only via the button above, never the
/// default view. Same podium and same rows as the own-rank board, so the
/// two never look like different products.
class GlobalLeaderboardScreen extends StatefulWidget {
  /// The caller and their friends instead of everyone: an "add a friend"
  /// button, and a long press removes one.
  final bool friends;
  const GlobalLeaderboardScreen({super.key, this.friends = false});

  @override
  State<GlobalLeaderboardScreen> createState() => _GlobalLeaderboardScreenState();
}

class _GlobalLeaderboardScreenState extends State<GlobalLeaderboardScreen> {
  bool _isLoading = true;
  String? _loadError;
  Leaderboard? _board;

  String get _cacheKey => widget.friends ? 'rating-friends' : 'rating-global';

  Future<void> _addFriend() async {
    final controller = TextEditingController();
    final id = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Добавить друга')),
        content: TextField(
          key: const ValueKey('friend-id-field'),
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: tr('ID друга'),
            hintText: tr('9 цифр из его профиля'),
            prefixIcon: const Icon(Icons.badge_outlined),
          ),
        ),
        actions: [
          TextButton.icon(
            key: const ValueKey('scan-friend'),
            onPressed: () => Navigator.of(ctx).pop(-1),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: Text(tr('Сканировать')),
          ),
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(tr('Отмена'))),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(int.tryParse(controller.text.replaceAll(RegExp(r'\D'), ''))),
            child: Text(tr('Добавить')),
          ),
        ],
      ),
    );
    if (id == null || !mounted) return;
    if (id == -1) {
      final added = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const ScanFriendScreen()));
      if (added == true) _load();
      return;
    }
    try {
      await ApiClient.instance.addFriend(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Друг добавлен'))));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// Every friend in a list, each with a remove button.
  Future<void> _manageFriends() async {
    final friends = [for (final e in _board?.entries ?? const <LeaderboardEntry>[]) if (!e.isMe) e];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final f in friends)
              ListTile(
                leading: Icon(Icons.person_rounded, color: AppColors.primary),
                title: Text(f.login, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(tr('{0} очков', [f.totalPoints])),
                trailing: IconButton(
                  icon: Icon(Icons.person_remove_rounded, color: AppColors.danger),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _removeFriend(f);
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _removeFriend(LeaderboardEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Удалить {0} из друзей?', [entry.login])),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(tr('Отмена'))),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(tr('Удалить'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiClient.instance.removeFriend(entry.userId);
      _load();
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _board = SessionCache.get<Leaderboard>(_cacheKey);
    _isLoading = _board == null;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = _board == null;
      _loadError = null;
    });
    try {
      final board = widget.friends
          ? await ApiClient.instance.fetchFriendsLeaderboard()
          : await ApiClient.instance.fetchGlobalLeaderboard();
      SessionCache.put(_cacheKey, board);
      if (!mounted) return;
      setState(() {
        _board = board;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (_board == null) _loadError = tr('Не удалось загрузить рейтинг');
      });
    }
  }

  Future<void> _editStatus() async {
    final saved = await showStatusPicker(context);
    if (saved != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.friends ? tr('Друзья') : tr('Глобальный рейтинг'),
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
        ),
        iconTheme: IconThemeData(color: AppColors.primaryDark),
        actions: [
          if (widget.friends && (_board?.entries.length ?? 0) > 1)
            IconButton(
              key: const ValueKey('manage-friends'),
              tooltip: tr('Управлять друзьями'),
              icon: Icon(Icons.manage_accounts_rounded, color: AppColors.primary),
              onPressed: _manageFriends,
            ),
        ],
      ),
      body: SafeArea(child: RefreshIndicator(onRefresh: _load, child: _buildBody())),
      floatingActionButton: widget.friends
          ? FloatingActionButton.extended(
              key: const ValueKey('add-friend'),
              onPressed: _addFriend,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: Text(tr('Добавить друга')),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const SkeletonList();
    }
    if (_loadError != null) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: Text(tr('Повторить'))),
              ],
            ),
          ),
        ],
      );
    }
    final entries = _board!.entries;
    if (widget.friends && entries.length <= 1) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(32, 80, 32, 24),
        children: [
          Icon(Icons.group_add_rounded, size: 56, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(
            tr('Добавьте друзей по их ID или QR-коду из профиля и соревнуйтесь вместе'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: AppColors.secondaryText),
          ),
        ],
      );
    }
    if (entries.isEmpty) {
      return Center(
        child: Text(tr('Рейтинг пока пуст'), style: TextStyle(color: AppColors.secondaryText)),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        LeaderboardPodium(entries: entries, onEditMyStatus: _editStatus),
        const SizedBox(height: 16),
        for (final entry in entries.skip(LeaderboardPodium.placeCount))
          LeaderboardRow(entry: entry, accentColor: AppColors.primary, showRank: true, onEditMyStatus: _editStatus),
        if (widget.friends) const SizedBox(height: 72),
      ],
    );
  }
}
