import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/duel.dart';
import '../models/user_rating.dart';
import '../models/user_profile.dart';
import 'user_avatar.dart';
import '../services/streak_state.dart';
import '../theme/app_colors.dart';
import '../models/reward_spec.dart';
import '../services/disk_cache.dart';
import 'counted_chest.dart' show GreenButton;
import 'reward_chips.dart';

/// «Дуэль недели» on Главная: challenge a friend, answer a challenge, or watch
/// the score of the running duel. Hidden when duels are switched off.
class DuelCard extends StatefulWidget {
  const DuelCard({super.key});

  @override
  State<DuelCard> createState() => _DuelCardState();
}

class _DuelCardState extends State<DuelCard> {
  DuelState? _state = ApiClient.instance.cachedDuels();
  UserProfile? _me;
  bool _busy = false;
  int _seen = int.tryParse(DiskCache.get('duel-result-seen') ?? '') ?? 0;

  @override
  void initState() {
    super.initState();
    dailyGoalTick.addListener(_load);
    _load();
    ApiClient.instance
        .fetchMyProfile()
        .then((value) {
          if (mounted) setState(() => _me = value);
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    dailyGoalTick.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final state = await ApiClient.instance.fetchDuels();
    if (mounted && state != null) setState(() => _state = state);
  }

  Future<void> _act(Future<DuelState> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final state = await action();
      if (mounted) setState(() => _state = state);
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
          SnackBar(content: Text(tr('Не удалось. Проверьте интернет.'))),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The latest finished duel, until its result is closed or a new duel starts.
  Duel? get _result {
    final s = _state;
    if (s == null || s.current != null) return null;
    for (final d in s.recent) {
      if (d.status == 'finished') return d.id > _seen ? d : null;
    }
    return null;
  }

  void _closeResult() {
    final r = _result;
    if (r == null) return;
    DiskCache.put('duel-result-seen', '${r.id}');
    setState(() => _seen = r.id);
  }

  Future<void> _pickFriend() async {
    List<LeaderboardEntry> friends;
    try {
      friends = (await ApiClient.instance.fetchFriendsLeaderboard()).entries.where((e) => !e.isMe).toList();
    } catch (_) {
      friends = [];
    }
    if (!mounted) return;
    final chosen = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: friends.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  tr('Сначала добавьте друга в рейтинге'),
                  style: TextStyle(color: AppColors.secondaryText),
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                    child: Text(
                      tr('Кого вызвать?'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                  for (final f in friends)
                    ListTile(
                      key: ValueKey('duel-friend-${f.userId}'),
                      title: Text(
                        f.login,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      onTap: () => Navigator.of(ctx).pop(f.userId),
                    ),
                ],
              ),
      ),
    );
    if (chosen != null) _act(() => ApiClient.instance.challengeFriend(chosen));
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state == null || !state.enabled) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: DuelCardView(
        state: state,
        busy: _busy,
        me: _me,
        onChallenge: _pickFriend,
        result: _result,
        onNewDuel: () {
          _closeResult();
          _pickFriend();
        },
        onCloseResult: _closeResult,
        onAccept: (d) =>
            _act(() => ApiClient.instance.answerDuel(d.id, accept: true)),
        onDecline: (d) =>
            _act(() => ApiClient.instance.answerDuel(d.id, accept: false)),
      ),
    );
  }
}

class DuelCardView extends StatelessWidget {
  final DuelState state;
  final bool busy;
  final UserProfile? me;
  final VoidCallback onChallenge;
  final void Function(Duel) onAccept;
  final void Function(Duel) onDecline;

  /// A finished duel whose result the person has not closed yet (shown instead of the card).
  final Duel? result;
  final VoidCallback? onNewDuel;
  final VoidCallback? onCloseResult;
  const DuelCardView({
    super.key,
    required this.state,
    this.busy = false,
    this.me,
    required this.onChallenge,
    required this.onAccept,
    required this.onDecline,
    this.result,
    this.onNewDuel,
    this.onCloseResult,
  });

  @override
  Widget build(BuildContext context) {
    final d = state.current;
    final done = result;
    if (d == null && done != null) {
      return _ResultPanel(duel: done, rewards: state.rewards, me: me, onNew: onNewDuel, onClose: onCloseResult);
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.violetSurface, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sports_kabaddi_rounded, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                tr('Дуэль недели'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primaryDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (d == null) ...[
            Text(
              tr(
                'Вызовите друга: кто за неделю наберёт больше энергии, тот победил.',
              ),
              style: TextStyle(fontSize: 13, color: AppColors.secondaryText),
            ),
            const SizedBox(height: 4),
            _PrizeStrip(rewards: state.rewards),
            const SizedBox(height: 6),
            FilledButton(
              key: const ValueKey('duel-challenge'),
              onPressed: busy ? null : onChallenge,
              child: Text(tr('Вызвать друга')),
            ),
          ] else if (d.incoming) ...[
            Text(
              tr('{0} вызывает вас на дуэль', [d.opponentLogin]),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('duel-decline'),
                    onPressed: busy ? null : () => onDecline(d),
                    child: Text(tr('Отказаться')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('duel-accept'),
                    onPressed: busy ? null : () => onAccept(d),
                    child: Text(tr('Принять')),
                  ),
                ),
              ],
            ),
          ] else if (d.isPending) ...[
            Text(
              tr('Ждём ответа: {0}', [d.opponentLogin]),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: busy ? null : () => onDecline(d),
              child: Text(tr('Отозвать вызов')),
            ),
          ] else ...[
            _Score(duel: d, me: me),
            const SizedBox(height: 4),
            _PrizeStrip(rewards: state.rewards),
          ],
        ],
      ),
    );
  }
}

class _Score extends StatelessWidget {
  final Duel duel;
  final UserProfile? me;
  const _Score({required this.duel, required this.me});

  @override
  Widget build(BuildContext context) {
    final total = duel.myXp + duel.theirXp;
    final share = total == 0 ? 0.5 : duel.myXp / total;
    final days = duel.endsAt.difference(DateTime.now()).inDays + 1;
    final ahead = duel.myXp > duel.theirXp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _DuelPlayer(
                avatarUrl: me?.avatarUrl,
                login: me?.login ?? tr('Вы'),
                score: duel.myXp,
                color: ahead ? AppColors.success : AppColors.primaryDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DuelPlayer(
                avatarUrl: duel.opponentAvatarUrl,
                login: duel.opponentLogin,
                score: duel.theirXp,
                color: AppColors.primaryDark,
                alignEnd: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: share,
            minHeight: 10,
            backgroundColor: AppColors.dangerLight,
            color: AppColors.success,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          tr('Осталось дней: {0}', [days < 0 ? 0 : days]),
          style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
        ),
      ],
    );
  }
}

class _DuelPlayer extends StatelessWidget {
  final String? avatarUrl;
  final String login;
  final int score;
  final Color color;
  final bool alignEnd;
  const _DuelPlayer({
    required this.avatarUrl,
    required this.login,
    required this.score,
    required this.color,
    this.alignEnd = false,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: alignEnd
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!alignEnd) ...[
            UserAvatar(avatarUrl: avatarUrl, login: login, size: 30),
            const SizedBox(width: 7),
          ],
          Flexible(
            child: Text(
              login,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.secondaryText,
              ),
            ),
          ),
          if (alignEnd) ...[
            const SizedBox(width: 7),
            UserAvatar(avatarUrl: avatarUrl, login: login, size: 30),
          ],
        ],
      ),
      const SizedBox(height: 3),
      Text(
        '$score',
        style: TextStyle(
          fontSize: 25,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    ],
  );
}


/// What the winner and a draw get, in one line (scrolls sideways if it does not fit).
class _PrizeStrip extends StatelessWidget {
  final Map<String, List<RewardSpec>> rewards;
  const _PrizeStrip({required this.rewards});

  @override
  Widget build(BuildContext context) {
    final win = rewards['win'] ?? const <RewardSpec>[];
    final draw = rewards['draw'] ?? const <RewardSpec>[];
    if (win.isEmpty && draw.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      key: const ValueKey('duel-prizes'),
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: 6, bottom: 6, right: 8),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (win.isNotEmpty) ...[
          const Text('🏆', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 8),
          for (final r in win) Padding(padding: const EdgeInsets.only(right: 8), child: RewardSlot(reward: r, side: 44)),
        ],
        if (win.isNotEmpty && draw.isNotEmpty) Container(width: 1, height: 28, margin: const EdgeInsets.only(right: 10, left: 2), color: AppColors.violetSurface),
        if (draw.isNotEmpty) ...[
          const Text('🤝', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 8),
          for (final r in draw) Padding(padding: const EdgeInsets.only(right: 8), child: RewardSlot(reward: r, side: 44, silver: true)),
        ],
      ]),
    );
  }
}

/// The end of a duel: who won, the score, what was won, and a button for a new duel.
class _ResultPanel extends StatelessWidget {
  final Duel duel;
  final Map<String, List<RewardSpec>> rewards;
  final UserProfile? me;
  final VoidCallback? onNew;
  final VoidCallback? onClose;
  const _ResultPanel({required this.duel, required this.rewards, required this.me, this.onNew, this.onClose});

  @override
  Widget build(BuildContext context) {
    final won = duel.won;
    final key = won == true ? 'win' : won == false ? 'lose' : 'draw';
    final prizes = rewards[key] ?? const <RewardSpec>[];
    final title = won == true ? '🏆 ${tr('Победа!')}' : won == false ? tr('Дуэль окончена') : '🤝 ${tr('Ничья')}';
    return Container(
      key: const ValueKey('duel-result'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(colors: [Color(0xFF3D2B8F), Color(0xFF1E1560)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: won == true ? const Color(0xFFFFD54F) : Colors.white)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _ResultSide(login: me?.login ?? tr('Вы'), avatarUrl: me?.avatarUrl, dim: won == false ? false : false)),
          Text('${duel.myXp} : ${duel.theirXp}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)),
          Expanded(child: _ResultSide(login: duel.opponentLogin, avatarUrl: duel.opponentAvatarUrl, dim: won == true)),
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Text(won == true ? '🏆' : won == false ? '🎯' : '🤝', style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Expanded(
              child: prizes.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(tr('В этот раз без награды'), style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    )
                  : RewardChips(rewards: prizes, size: 22, silver: won != true),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        GreenButton(key: const ValueKey('duel-new'), label: tr('Новая дуэль'), onTap: onNew, padding: const EdgeInsets.symmetric(vertical: 12)),
        TextButton(
          key: const ValueKey('duel-result-close'),
          onPressed: onClose,
          child: Text(tr('Закрыть'), style: const TextStyle(color: Colors.white70)),
        ),
      ]),
    );
  }
}

class _ResultSide extends StatelessWidget {
  final String login;
  final String? avatarUrl;
  final bool dim;
  const _ResultSide({required this.login, required this.avatarUrl, required this.dim});

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: dim ? 0.55 : 1,
        child: Column(children: [
          UserAvatar(avatarUrl: avatarUrl, login: login, size: 40),
          const SizedBox(height: 3),
          Text(login, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      );
}
