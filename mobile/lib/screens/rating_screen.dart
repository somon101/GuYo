import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/user_rating.dart';
import '../theme/app_colors.dart';
import '../widgets/rank_icon.dart';
import '../widgets/user_avatar.dart';
import '../widgets/user_name.dart';
import 'all_ranks_screen.dart';

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
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final board = await ApiClient.instance.fetchMyRankLeaderboard();
      if (!mounted) return;
      setState(() {
        _board = board;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Не удалось загрузить рейтинг';
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
      return ListView(children: const [SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))]);
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
                FilledButton(onPressed: _load, child: const Text('Повторить')),
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
        LeaderboardHeader(title: 'Рейтинг', onOpenGlobal: _openGlobal),
        if (rank == null)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppShapes.cardRadius),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: const Text(
                'Пока нет ранга — начните учить слова, чтобы попасть в рейтинг',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.secondaryText),
              ),
            ),
          )
        else ...[
          if (board.entries.isNotEmpty) ...[
            const SizedBox(height: 4),
            LeaderboardPodium(entries: board.entries),
          ],
          const SizedBox(height: 14),
          _RankCard(rank: rank, color: color, onTap: _rating == null ? null : _openAllRanks),
          const SizedBox(height: 14),
          if (board.entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Пока никто не в этом ранге',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.secondaryText),
              ),
            )
          else
            // Everyone the podium didn't already show. Every row in this
            // board shares the caller's own rank, so a per-row rank badge
            // would repeat the card above on every line.
            for (final entry in board.entries.skip(LeaderboardPodium.placeCount))
              LeaderboardRow(entry: entry, accentColor: color),
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

  const LeaderboardHeader({super.key, required this.title, this.onOpenGlobal});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
          ),
        ),
        if (onOpenGlobal != null)
          Material(
            color: Colors.white,
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
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.public, size: 16, color: AppColors.primary),
                    SizedBox(width: 6),
                    Text(
                      'Глобальный рейтинг',
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

  const LeaderboardPodium({super.key, required this.entries});

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
              Expanded(child: _PodiumPlace(entry: second, place: 2)),
              Expanded(child: _PodiumPlace(entry: first, place: 1)),
              Expanded(child: _PodiumPlace(entry: third, place: 3)),
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

  const _PodiumPlace({required this.entry, required this.place});

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

    return Padding(
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
                Positioned(
                  bottom: 0,
                  child: Container(
                    width: isFirst ? 28 : 24,
                    height: isFirst ? 28 : 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
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
              Icon(Icons.stars_rounded, size: isFirst ? 15 : 13, color: AppColors.rewardText),
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

  const _RankCard({required this.rank, required this.color, required this.onTap});

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
                      'Топ-100 «${rank.name}»',
                      style: const TextStyle(fontSize: 12, color: AppColors.secondaryText),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
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

  const LeaderboardRow({
    super.key,
    required this.entry,
    required this.accentColor,
    this.showRank = false,
  });

  @override
  Widget build(BuildContext context) {
    final rowRank = entry.rank;
    final rowColor = rowRank != null ? parseHexColor(rowRank.color) : accentColor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: entry.isMe ? AppColors.primary.withValues(alpha: 0.07) : Colors.white,
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
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.secondaryText),
              ),
            ),
            const SizedBox(width: 6),
            UserAvatar(avatarUrl: entry.avatarUrl, login: entry.login, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
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
            ),
            if (showRank && rowRank != null) ...[
              RankIcon(rank: rowRank, color: rowColor, size: 22),
              const SizedBox(width: 8),
            ],
            Text(
              '${entry.totalPoints}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.rewardText),
            ),
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
  const GlobalLeaderboardScreen({super.key});

  @override
  State<GlobalLeaderboardScreen> createState() => _GlobalLeaderboardScreenState();
}

class _GlobalLeaderboardScreenState extends State<GlobalLeaderboardScreen> {
  bool _isLoading = true;
  String? _loadError;
  Leaderboard? _board;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final board = await ApiClient.instance.fetchGlobalLeaderboard();
      if (!mounted) return;
      setState(() {
        _board = board;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Не удалось загрузить рейтинг';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Глобальный рейтинг',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
        ),
        iconTheme: const IconThemeData(color: AppColors.primaryDark),
      ),
      body: SafeArea(child: RefreshIndicator(onRefresh: _load, child: _buildBody())),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return ListView(children: const [SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))]);
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
                FilledButton(onPressed: _load, child: const Text('Повторить')),
              ],
            ),
          ),
        ],
      );
    }
    final entries = _board!.entries;
    if (entries.isEmpty) {
      return const Center(
        child: Text('Рейтинг пока пуст', style: TextStyle(color: AppColors.secondaryText)),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        LeaderboardPodium(entries: entries),
        const SizedBox(height: 16),
        for (final entry in entries.skip(LeaderboardPodium.placeCount))
          LeaderboardRow(entry: entry, accentColor: AppColors.primary, showRank: true),
      ],
    );
  }
}
