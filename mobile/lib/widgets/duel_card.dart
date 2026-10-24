import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/duel.dart';
import '../models/user_rating.dart';
import '../models/user_profile.dart';
import 'user_avatar.dart';
import '../services/streak_state.dart';
import '../theme/app_colors.dart';
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
            .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Не удалось. Проверьте интернет.'))),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
  const DuelCardView({
    super.key,
    required this.state,
    this.busy = false,
    this.me,
    required this.onChallenge,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final d = state.current;
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
          if (state.rewards.values.any((r) => r.isNotEmpty)) ...[
            const SizedBox(height: 8),
            for (final e in const [('win', 'Победа'), ('draw', 'Ничья'), ('lose', 'Поражение')])
              if ((state.rewards[e.$1] ?? const []).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    SizedBox(
                      width: 84,
                      child: Text(tr(e.$2), style: TextStyle(fontSize: 12, color: AppColors.secondaryText)),
                    ),
                    Expanded(child: RewardChips(rewards: state.rewards[e.$1]!, color: AppColors.primaryDark, size: 18)),
                  ]),
                ),
          ],
          const SizedBox(height: 10),
          if (d == null) ...[
            Text(
              tr(
                'Вызовите друга: кто за неделю наберёт больше энергии, тот победил.',
              ),
              style: TextStyle(fontSize: 13, color: AppColors.secondaryText),
            ),
            const SizedBox(height: 10),
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
          ] else
            _Score(duel: d, me: me),
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
