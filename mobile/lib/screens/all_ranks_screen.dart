import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/user_rating.dart';
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
      return const Center(child: Text('Уровни ещё не настроены', style: TextStyle(color: Colors.black54)));
    }

    final totalPoints = widget.rating.totalPoints;
    final currentId = widget.rating.rank?.id;
    // The current rank's OWN index in the full ladder -- everything before
    // it is "passed", everything after is "future". Falls back to -1 (all
    // future) only if the caller genuinely has no current rank at all
    // (e.g. a gap in the admin's configured ranges), matching how the
    // "Рейтинг" block already renders that same edge case.
    final currentIndex = currentId == null ? -1 : _ranks.indexWhere((r) => r.id == currentId);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      itemCount: _ranks.length,
      itemBuilder: (context, index) {
        final rank = _ranks[index];
        final status = index < currentIndex
            ? _RankStatus.passed
            : index == currentIndex
                ? _RankStatus.current
                : _RankStatus.future;
        return _RankNode(
          rank: rank,
          status: status,
          isFirst: index == 0,
          isLast: index == _ranks.length - 1,
          segmentToNextFilled: index < currentIndex,
          totalPoints: totalPoints,
        );
      },
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
    final connectorColor = isPassed ? color : Colors.grey.shade300;

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
                            child: Icon(Icons.check_circle, color: Colors.green.shade600, size: 18),
                          ),
                        ),
                      if (status == _RankStatus.future)
                        Positioned(
                          bottom: -2,
                          right: -2,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey.shade400),
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
        color: isCurrent ? color.withValues(alpha: 0.08) : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isCurrent ? color.withValues(alpha: 0.5) : Colors.grey.shade200, width: isCurrent ? 1.5 : 1),
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
                    color: isFuture ? Colors.black45 : Colors.black87,
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
                Icon(Icons.check_circle, color: Colors.green.shade600, size: 18)
              else
                Icon(Icons.lock_outline, color: Colors.grey.shade400, size: 16),
            ],
          ),
          const SizedBox(height: 3),
          Text(_pointsRangeLabel(), style: const TextStyle(fontSize: 12, color: Colors.black45)),
          if (isCurrent && rank.maxPoints != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ((totalPoints - rank.minPoints) / (rank.maxPoints! + 1 - rank.minPoints)).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Осталось ${rank.maxPoints! + 1 - totalPoints} очков до следующего уровня',
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
          ] else if (isFuture) ...[
            const SizedBox(height: 4),
            Text(
              'Нужно ещё ${rank.minPoints - totalPoints} очков',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}
