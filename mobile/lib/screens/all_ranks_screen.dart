import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/user_rating.dart';
import '../theme/app_colors.dart';
import '../widgets/rank_icon.dart';

/// "Все уровни" -- the full rank ladder as one connected progress path,
/// reached from the Profile screen's "Рейтинг" block. Purely a richer view
/// over data the "Рейтинг" block already has: GET /rating/ranks for the
/// full ladder (same ordering/rows current_rank_for_points itself
/// classifies against) plus the caller's own current rank/points, already
/// fetched once by ProfileScreen's fetchMyRating and passed straight in --
/// this screen never re-decides who the user's current rank is, it only
/// locates that SAME rank (by id) within the full list to know which
/// ranks are behind, current, or still ahead.
class AllRanksScreen extends StatefulWidget {
  final UserRating rating;
  const AllRanksScreen({super.key, required this.rating});

  @override
  State<AllRanksScreen> createState() => _AllRanksScreenState();
}

class _AllRanksScreenState extends State<AllRanksScreen> {
  bool _isLoading = true;
  String? _loadError;
  List<RankSummary> _ranks = [];

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
      final ranks = await ApiClient.instance.fetchAllRanks();
      if (!mounted) return;
      setState(() {
        _ranks = ranks;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Не удалось загрузить уровни';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Все уровни')),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
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
      );
    }
    if (_ranks.isEmpty) {
      return const Center(child: Text('Уровни ещё не настроены', style: TextStyle(color: AppColors.secondaryText)));
    }

    final totalPoints = widget.rating.totalPoints;
    final currentId = widget.rating.rank?.id;
    // The current rank's OWN index in the full ladder -- everything before
    // it is "passed", everything after is "future". Falls back to -1 (all
    // future) only if the caller genuinely has no current rank at all
    // (e.g. a gap in the admin's configured ranges), matching how the
    // "Рейтинг" block already renders that same edge case.
    final currentIndex = currentId == null ? -1 : _ranks.indexWhere((r) => r.id == currentId);

    final history = widget.rating.history;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        for (var index = 0; index < _ranks.length; index++)
          _RankNode(
            rank: _ranks[index],
            status: index < currentIndex
                ? _RankStatus.passed
                : index == currentIndex
                    ? _RankStatus.current
                    : _RankStatus.future,
            isFirst: index == 0,
            isLast: index == _ranks.length - 1,
            segmentToNextFilled: index < currentIndex,
            totalPoints: totalPoints,
          ),
        // Past seasons live here rather than on the Profile screen: they're
        // the same rating system's own history, and this is the screen that
        // shows that system in full.
        if (history.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text(
            'История сезонов',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
          ),
          const SizedBox(height: 10),
          for (final entry in history) _SeasonHistoryRow(entry: entry),
        ],
      ],
    );
  }
}

enum _RankStatus { passed, current, future }

class _RankNode extends StatelessWidget {
  final RankSummary rank;
  final _RankStatus status;
  final bool isFirst;
  final bool isLast;
  // Whether the connector line BELOW this node should render as "already
  // walked" (full color) rather than "not yet reached" (grey) -- true only
  // when this node itself is already passed, since the segment leading
  // away from the CURRENT node is still ahead of the user.
  final bool segmentToNextFilled;
  final int totalPoints;

  const _RankNode({
    required this.rank,
    required this.status,
    required this.isFirst,
    required this.isLast,
    required this.segmentToNextFilled,
    required this.totalPoints,
  });

  @override
  Widget build(BuildContext context) {
    final color = parseHexColor(rank.color);
    final isCurrent = status == _RankStatus.current;
    final isPassed = status == _RankStatus.passed;
    final iconSize = isCurrent ? 72.0 : 56.0;
    final connectorColor = isPassed ? color : const Color(0xFFEDEFF7);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              SizedBox(
                height: isFirst ? 0 : 16,
                child: isFirst ? null : VerticalDivider(width: 2, thickness: 2, color: connectorColor),
              ),
              Container(
                padding: EdgeInsets.all(isCurrent ? 4 : 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: isCurrent ? color : Colors.transparent, width: isCurrent ? 3 : 0),
                  boxShadow: isCurrent
                      ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 16, spreadRadius: 1)]
                      : null,
                ),
                child: Opacity(
                  opacity: status == _RankStatus.future ? 0.45 : 1,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      RankIcon(rank: rank, color: color, size: iconSize),
                      if (isPassed)
                        Positioned(
                          bottom: -2,
                          right: -2,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                            child: const Icon(Icons.check_circle, color: AppColors.success, size: 18),
                          ),
                        ),
                      if (status == _RankStatus.future)
                        Positioned(
                          bottom: -2,
                          right: -2,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFB9BEDA)),
                            child: const Icon(Icons.lock, color: Colors.white, size: 12),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (!isLast) Expanded(child: VerticalDivider(width: 2, thickness: 2, color: connectorColor)),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 24, top: isFirst ? 0 : 0),
              child: _RankCard(rank: rank, status: status, color: color, totalPoints: totalPoints),
            ),
          ),
        ],
      ),
    );
  }
}

class _RankCard extends StatelessWidget {
  final RankSummary rank;
  final _RankStatus status;
  final Color color;
  final int totalPoints;

  const _RankCard({required this.rank, required this.status, required this.color, required this.totalPoints});

  String _pointsRangeLabel() {
    if (rank.maxPoints == null) return 'от ${rank.minPoints} очков';
    return '${rank.minPoints}–${rank.maxPoints} очков';
  }

  @override
  Widget build(BuildContext context) {
    final isCurrent = status == _RankStatus.current;
    final isFuture = status == _RankStatus.future;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isCurrent ? color.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isCurrent ? color.withValues(alpha: 0.5) : const Color(0xFFEDEFF7), width: isCurrent ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  rank.name,
                  style: TextStyle(
                    fontSize: isCurrent ? 18 : 15,
                    fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w700,
                    color: isFuture ? AppColors.secondaryText : AppColors.primaryDark,
                  ),
                ),
              ),
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
                  child: const Text(
                    'Вы здесь',
                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                )
              else if (status == _RankStatus.passed)
                const Icon(Icons.check_circle, color: AppColors.success, size: 18)
              else
                const Icon(Icons.lock_outline, color: Color(0xFFB9BEDA), size: 16),
            ],
          ),
          const SizedBox(height: 3),
          Text(_pointsRangeLabel(), style: const TextStyle(fontSize: 12, color: AppColors.secondaryText)),
          if (isCurrent && rank.maxPoints != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ((totalPoints - rank.minPoints) / (rank.maxPoints! + 1 - rank.minPoints)).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: const Color(0xFFEDEFF7),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Осталось ${rank.maxPoints! + 1 - totalPoints} очков до следующего уровня',
              style: const TextStyle(fontSize: 11, color: AppColors.secondaryText),
            ),
          ] else if (isFuture) ...[
            const SizedBox(height: 4),
            Text(
              'Нужно ещё ${rank.minPoints - totalPoints} очков',
              style: const TextStyle(fontSize: 11, color: AppColors.secondaryText, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}


/// One finished season's frozen result -- never recomputed from the user's
/// CURRENT points (see the backend's SeasonHistory: that snapshot is fixed
/// the moment a season ends).
class _SeasonHistoryRow extends StatelessWidget {
  final SeasonHistoryEntry entry;
  const _SeasonHistoryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final rank = entry.rank;
    final color = rank != null ? parseHexColor(rank.color) : AppColors.secondaryText;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDEFF7)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              entry.seasonName,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (rank != null) ...[
            Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
            const SizedBox(width: 6),
            Text(rank.name, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w700)),
            const SizedBox(width: 10),
          ],
          Text(
            '${entry.points}',
            style: const TextStyle(fontSize: 13, color: AppColors.secondaryText, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
