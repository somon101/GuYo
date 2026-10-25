import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/team.dart';
import '../theme/app_colors.dart';
import '../widgets/season_pass_ui.dart';
import '../widgets/user_avatar.dart';
import '../widgets/user_name.dart';
import 'season_pass_screen.dart' show rewardSentence;

const _teamGradient = [Color(0xFF14B8A6), Color(0xFF2563EB)];

String _goalText(TeamGoal g) => switch (g.metric) {
  'word' => tr('Вместе выучить слов: {0}', [g.target]),
  'lesson' => tr('Вместе пройти уроков: {0}', [g.target]),
  'review' => tr('Вместе ответить в «Повторить сегодня»: {0}', [g.target]),
  'quest' => tr('Вместе выполнить заданий квестов: {0}', [g.target]),
  'streak' => tr('Вместе набрать дней серии: {0}', [g.target]),
  _ => '${g.metric}: ${g.target}',
};

const _metricIcons = <String, IconData>{
  'word': Icons.menu_book_rounded,
  'lesson': Icons.school_rounded,
  'review': Icons.replay_rounded,
  'quest': Icons.flag_rounded,
  'streak': Icons.local_fire_department_rounded,
};

/// «Команда»: friends work on shared goals for the week and for the season;
/// everything is decided on the server, this screen shows it and sends actions.
class TeamScreen extends StatefulWidget {
  /// Shown at once with no request (used by tests and previews).
  final TeamState? initial;
  const TeamScreen({super.key, this.initial});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen>
    with SingleTickerProviderStateMixin {
  TeamState? _state;
  bool _loading = true;
  bool _busy = false;
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _state = widget.initial;
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await ApiClient.instance.fetchMyTeam();
    if (!mounted) return;
    setState(() {
      _state = s;
      _loading = false;
    });
  }

  void _snack(String text) {
    if (mounted)
      ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _act(Future<TeamState> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final s = await action();
      if (mounted) setState(() => _state = s);
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack(tr('Не удалось. Проверьте интернет.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _claim(TeamGoal goal) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await ApiClient.instance.claimTeamGoal(
        goal.scope,
        goal.id,
      );
      if (!mounted) return;
      setState(() => _state = result.state);
      final reward = goal.reward;
      final style = reward != null
          ? rewardStyle(reward)
          : const RewardStyle(
              [Color(0xFF14B8A6), Color(0xFF2563EB)],
              Icons.bolt_rounded,
              '⚡',
            );
      final parts = [
        if (result.xp > 0) '+${result.xp} ⚡',
        if (reward != null) rewardSentence(reward),
      ];
      await showRewardDialog(
        context,
        style: style,
        title: tr('Награда получена!'),
        text: parts.join(' · '),
      );
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack(tr('Не удалось. Проверьте интернет.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final result = await showModalBottomSheet<(String, bool)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CreateSheet(),
    );
    if (result != null)
      _act(() => ApiClient.instance.createTeam(result.$1, isOpen: result.$2));
  }

  Future<void> _find() async {
    final id = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _FindSheet(),
    );
    if (id != null) _act(() => ApiClient.instance.joinTeam(id));
  }

  Future<void> _invite(Team team) async {
    final taken = team.members.map((m) => m.userId).toSet();
    final id = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InviteSheet(taken: taken),
    );
    if (id != null) {
      await _act(() => ApiClient.instance.inviteToTeam(id));
      _snack(tr('Приглашение отправлено'));
    }
  }

  Future<void> _menu(Team team) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (team.isOwner) ...[
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: Text(tr('Переименовать')),
                onTap: () => Navigator.pop(context, 'rename'),
              ),
              ListTile(
                leading: Icon(
                  team.isOpen ? Icons.lock_rounded : Icons.lock_open_rounded,
                ),
                title: Text(
                  team.isOpen
                      ? tr('Закрыть для вступления')
                      : tr('Открыть для вступления'),
                ),
                onTap: () => Navigator.pop(context, 'toggle'),
              ),
            ],
            ListTile(
              leading: Icon(Icons.logout_rounded, color: AppColors.danger),
              title: Text(
                tr('Выйти из команды'),
                style: TextStyle(color: AppColors.danger),
              ),
              onTap: () => Navigator.pop(context, 'leave'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'toggle') {
      _act(() => ApiClient.instance.updateTeam(isOpen: !team.isOpen));
    } else if (choice == 'leave') {
      _act(() => ApiClient.instance.leaveTeam());
    } else if (choice == 'rename') {
      final name = await _askName(team.name);
      if (name != null) _act(() => ApiClient.instance.updateTeam(name: name));
    }
  }

  Future<String?> _askName(String current) {
    final controller = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr('Название команды')),
        content: TextField(
          controller: controller,
          maxLength: 24,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Отмена')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(tr('Сохранить')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(tr('Команда')),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actions: [
          if (state?.team != null)
            IconButton(
              icon: const Icon(Icons.more_vert_rounded),
              onPressed: () => _menu(state!.team!),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : state == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(tr('Не удалось загрузить данные')),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: state.team == null
                  ? _noTeam(state)
                  : _withTeam(state.team!, state),
            ),
    );
  }

  Widget _noTeam(TeamState state) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: [
        for (final invite in state.invites)
          _InviteCard(
            invite: invite,
            busy: _busy,
            onAccept: () =>
                _act(() => ApiClient.instance.acceptTeamInvite(invite.teamId)),
            onDecline: () =>
                _act(() => ApiClient.instance.declineTeamInvite(invite.teamId)),
          ),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _teamGradient,
            ),
            boxShadow: [
              BoxShadow(
                color: _teamGradient.last.withValues(alpha: 0.35),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              const Icon(Icons.groups_rounded, size: 72, color: Colors.white),
              const SizedBox(height: 10),
              Text(
                tr('Играйте вместе'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tr(
                  'Соберите команду из друзей: общие цели недели и сезона, бонусная энергия и командный значок',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _create,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _teamGradient.last,
                  ),
                  child: Text(
                    tr('Создать команду'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _busy ? null : _find,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    tr('Найти команду'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _withTeam(Team team, TeamState state) {
    final maxXp = team.members.fold<int>(
      1,
      (m, x) => x.weekXp > m ? x.weekXp : m,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _teamGradient,
            ),
            boxShadow: [
              BoxShadow(
                color: _teamGradient.last.withValues(alpha: 0.35),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      team.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      team.isOpen ? tr('Открыта') : tr('По приглашению'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (final m in team.members)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: UserAvatar(
                          avatarUrl: m.avatarUrl,
                          login: m.login,
                          size: 40,
                        ),
                      ),
                    ),
                  if (team.isOwner)
                    for (var i = team.members.length; i < state.capacity; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InkWell(
                          onTap: _busy ? null : () => _invite(team),
                          customBorder: const CircleBorder(),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                tr('В команде: {0} из {1}', [
                  team.members.length,
                  state.capacity,
                ]),
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (team.seasonGoal != null)
          _SeasonGoalCard(
            goal: team.seasonGoal!,
            pulse: _pulseController,
            busy: _busy,
            onClaim: () => _claim(team.seasonGoal!),
          ),
        _Title(tr('Цели недели')),
        if (team.weekGoals.isEmpty)
          Text(
            tr('На этой неделе целей нет'),
            style: TextStyle(color: AppColors.secondaryText),
          )
        else
          for (final g in team.weekGoals)
            _GoalCard(
              goal: g,
              pulse: _pulseController,
              busy: _busy,
              onClaim: () => _claim(g),
            ),
        const SizedBox(height: 16),
        _Title(tr('Вклад за неделю')),
        for (final m in team.members)
          _MemberRow(
            member: m,
            maxXp: maxXp,
            canKick: team.isOwner && !m.isOwner,
            onKick: () =>
                _act(() => ApiClient.instance.kickTeamMember(m.userId)),
          ),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  final String text;
  const _Title(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w900,
        color: AppColors.primaryDark,
      ),
    ),
  );
}

class _GoalCard extends StatelessWidget {
  final TeamGoal goal;
  final Animation<double> pulse;
  final bool busy;
  final VoidCallback onClaim;
  const _GoalCard({
    required this.goal,
    required this.pulse,
    required this.busy,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    final value = goal.target == 0
        ? 1.0
        : (goal.progress / goal.target).clamp(0.0, 1.0);
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: goal.claimable
                ? _teamGradient.last.withValues(alpha: 0.5 + 0.5 * pulse.value)
                : AppColors.cardBorder,
            width: goal.claimable ? 2 : 1,
          ),
          boxShadow: goal.claimable
              ? [
                  BoxShadow(
                    color: _teamGradient.last.withValues(
                      alpha: 0.18 + 0.2 * pulse.value,
                    ),
                    blurRadius: 14,
                  ),
                ]
              : AppShapes.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(colors: _teamGradient),
              ),
              child: Icon(
                _metricIcons[goal.metric] ?? Icons.bolt_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _goalText(goal),
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 9,
                      backgroundColor: AppColors.progressTrack,
                      color: goal.claimed
                          ? AppColors.success
                          : _teamGradient.last,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${goal.progress} / ${goal.target} · +${goal.xp} ⚡${goal.reward != null ? ' · ${rewardSentence(goal.reward!)}' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (goal.claimed)
              Icon(
                Icons.check_circle_rounded,
                color: AppColors.success,
                size: 30,
              )
            else if (goal.claimable)
              FilledButton(
                onPressed: busy ? null : onClaim,
                child: Text(tr('Забрать')),
              ),
          ],
        ),
      ),
    );
  }
}

class _SeasonGoalCard extends StatelessWidget {
  final TeamGoal goal;
  final Animation<double> pulse;
  final bool busy;
  final VoidCallback onClaim;
  const _SeasonGoalCard({
    required this.goal,
    required this.pulse,
    required this.busy,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    final value = goal.target == 0
        ? 1.0
        : (goal.progress / goal.target).clamp(0.0, 1.0);
    final reward = goal.reward;
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFF3A2A00), Color(0xFF6B4B00)],
        ),
        border: Border.all(color: const Color(0xFFFFD54F), width: 1.6),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFB300).withValues(alpha: 0.28),
            blurRadius: 18,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (reward != null && reward.type == 'badge')
                BadgeGlyph(badgeKey: reward.key ?? 'shield', size: 48)
              else
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFFFFE066), Color(0xFFFF9800)],
                    ),
                  ),
                  child: const Icon(
                    Icons.emoji_events_rounded,
                    color: Color(0xFF5A3B00),
                    size: 28,
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('Цель сезона'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFFFE066),
                      ),
                    ),
                    Text(
                      _goalText(goal),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 10,
              backgroundColor: Colors.white24,
              color: const Color(0xFFFFD54F),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${goal.progress} / ${goal.target} · +${goal.xp} ⚡${reward != null ? ' · ${rewardSentence(reward)}' : ''}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ),
              if (goal.claimed)
                const Icon(Icons.check_circle_rounded, color: Color(0xFF5EE0A0))
              else if (goal.claimable)
                FilledButton(
                  onPressed: busy ? null : onClaim,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD54F),
                    foregroundColor: const Color(0xFF5A3B00),
                  ),
                  child: Text(
                    tr('Забрать'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  final TeamMember member;
  final int maxXp;
  final bool canKick;
  final VoidCallback onKick;
  const _MemberRow({
    required this.member,
    required this.maxXp,
    required this.canKick,
    required this.onKick,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          UserAvatar(
            avatarUrl: member.avatarUrl,
            login: member.login,
            size: 40,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: UserNameText(
                        member.login,
                        isPremium: false,
                        badge: member.badge,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ),
                    if (member.isOwner) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.star_rounded,
                        size: 16,
                        color: AppColors.warning,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: maxXp == 0 ? 0 : member.weekXp / maxXp,
                    minHeight: 7,
                    backgroundColor: AppColors.progressTrack,
                    color: _teamGradient.first,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '⚡ ${member.weekXp}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          if (canKick)
            IconButton(
              tooltip: tr('Исключить'),
              icon: Icon(
                Icons.person_remove_rounded,
                size: 20,
                color: AppColors.muted,
              ),
              onPressed: onKick,
            ),
        ],
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  final TeamInvite invite;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  const _InviteCard({
    required this.invite,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _teamGradient.last, width: 1.6),
      ),
      child: Row(
        children: [
          const Icon(Icons.mail_rounded, color: Color(0xFF2563EB)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr('{0} зовёт вас в команду «{1}»', [
                invite.fromLogin,
                invite.teamName,
              ]),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryDark,
              ),
            ),
          ),
          IconButton(
            onPressed: busy ? null : onDecline,
            icon: Icon(Icons.close_rounded, color: AppColors.muted),
          ),
          FilledButton(
            onPressed: busy ? null : onAccept,
            child: Text(tr('Принять')),
          ),
        ],
      ),
    );
  }
}

// --- Sheets ---------------------------------------------------------------------------

class _SheetFrame extends StatelessWidget {
  final String title;
  final Widget child;
  const _SheetFrame({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(28),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primaryDark,
                ),
              ),
              const SizedBox(height: 14),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateSheet extends StatefulWidget {
  const _CreateSheet();

  @override
  State<_CreateSheet> createState() => _CreateSheetState();
}

class _CreateSheetState extends State<_CreateSheet> {
  final _name = TextEditingController();
  bool _open = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _name.text.trim().length >= 3;
    return _SheetFrame(
      title: tr('Новая команда'),
      child: Column(
        children: [
          TextField(
            controller: _name,
            maxLength: 24,
            autofocus: true,
            decoration: InputDecoration(labelText: tr('Название команды')),
            onChanged: (_) => setState(() {}),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Открыта для вступления')),
            subtitle: Text(
              tr('Любой сможет вступить, пока есть места'),
              style: const TextStyle(fontSize: 12),
            ),
            value: _open,
            onChanged: (v) => setState(() => _open = v),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: valid
                  ? () => Navigator.pop(context, (_name.text.trim(), _open))
                  : null,
              child: Text(tr('Создать команду')),
            ),
          ),
        ],
      ),
    );
  }
}

class _FindSheet extends StatefulWidget {
  const _FindSheet();

  @override
  State<_FindSheet> createState() => _FindSheetState();
}

class _FindSheetState extends State<_FindSheet> {
  List<OpenTeam>? _teams;

  @override
  void initState() {
    super.initState();
    ApiClient.instance
        .fetchOpenTeams()
        .then((t) {
          if (mounted) setState(() => _teams = t);
        })
        .catchError((_) {
          if (mounted) setState(() => _teams = []);
        });
  }

  @override
  Widget build(BuildContext context) {
    final teams = _teams;
    return _SheetFrame(
      title: tr('Открытые команды'),
      child: teams == null
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          : teams.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Text(tr('Открытых команд со свободными местами пока нет')),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final t in teams)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: _teamGradient),
                        ),
                        child: const Icon(
                          Icons.groups_rounded,
                          color: Colors.white,
                        ),
                      ),
                      title: Text(
                        t.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        tr('В команде: {0} из {1}', [t.members, t.capacity]),
                      ),
                      trailing: FilledButton(
                        onPressed: () => Navigator.pop(context, t.id),
                        child: Text(tr('Вступить')),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _InviteSheet extends StatefulWidget {
  final Set<int> taken;
  const _InviteSheet({required this.taken});

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  List<dynamic>? _friends;

  @override
  void initState() {
    super.initState();
    ApiClient.instance
        .fetchFriendsLeaderboard()
        .then((board) {
          if (mounted)
            setState(
              () => _friends = board.entries
                  .where((e) => !e.isMe && !widget.taken.contains(e.userId))
                  .toList(),
            );
        })
        .catchError((_) {
          if (mounted) setState(() => _friends = []);
        });
  }

  @override
  Widget build(BuildContext context) {
    final friends = _friends;
    return _SheetFrame(
      title: tr('Пригласить друга'),
      child: friends == null
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          : friends.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                tr(
                  'Нет друзей, которых можно пригласить. Добавьте друзей в рейтинге',
                ),
              ),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final f in friends)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: UserAvatar(
                        avatarUrl: f.avatarUrl,
                        login: f.login,
                        size: 40,
                      ),
                      title: Text(
                        f.login,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      trailing: FilledButton(
                        onPressed: () => Navigator.pop(context, f.userId),
                        child: Text(tr('Позвать')),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
