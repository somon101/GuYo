import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/user_rating.dart';
import '../widgets/rank_icon.dart';
import '../widgets/user_avatar.dart';

/// "Рейтинг" tab: shows only the leaderboard of the user's OWN current
/// rank -- there is no control anywhere on this screen to pick a
/// different one, by design (backend/app/routers/rating.py's
/// /rating/leaderboard always answers for the caller's own rank). Not
/// dictionary-scoped (rating is per-user, not per-language), same as
/// "Профиль".
class RatingScreen extends StatefulWidget {
  const RatingScreen({super.key});

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  bool _isLoading = true;
  String? _loadError;
  Leaderboard? _board;

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
  }

  Future<void> _openGlobal() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GlobalLeaderboardScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(onRefresh: _load, child: _buildBody()),
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
    final color = rank != null ? parseHexColor(rank.color) : Colors.grey;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        Row(
          children: [
            const Text('Рейтинг', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _openGlobal,
              icon: const Icon(Icons.public, size: 18),
              label: const Text('Глобальный рейтинг'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (rank == null)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'Пока нет ранга -- начните учить слова, чтобы попасть в рейтинг',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          )
        else ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                RankIcon(rank: rank, color: color, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(rank.name, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
                      const SizedBox(height: 2),
                      Text(
                        'Топ-100 «${rank.name}»',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (board.entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('Пока никто не в этом ранге', textAlign: TextAlign.center, style: TextStyle(color: Colors.black45)),
            )
          else
            for (final entry in board.entries) _LeaderboardRow(entry: entry, accentColor: color),
        ],
      ],
    );
  }
}

/// The global top-100 -- entered only via the button above, never the
/// default view.
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
      appBar: AppBar(title: const Text('Глобальный рейтинг')),
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
      return const Center(child: Text('Рейтинг пока пуст', style: TextStyle(color: Colors.black45)));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [for (final entry in entries) _LeaderboardRow(entry: entry, accentColor: Colors.indigo)],
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final LeaderboardEntry entry;
  final Color accentColor;
  const _LeaderboardRow({required this.entry, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final rowRank = entry.rank;
    final rowColor = rowRank != null ? parseHexColor(rowRank.color) : accentColor;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: entry.isMe ? accentColor.withValues(alpha: 0.1) : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: entry.isMe ? accentColor.withValues(alpha: 0.4) : Colors.grey.shade200),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '${entry.position}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black45),
            ),
          ),
          const SizedBox(width: 8),
          UserAvatar(avatarUrl: entry.avatarUrl, login: entry.login, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              entry.login,
              style: TextStyle(fontSize: 14, fontWeight: entry.isMe ? FontWeight.w800 : FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (rowRank != null) ...[
            RankIcon(rank: rowRank, color: rowColor, size: 22),
            const SizedBox(width: 6),
          ],
          Text('${entry.totalPoints}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: rowColor)),
        ],
      ),
    );
  }
}
