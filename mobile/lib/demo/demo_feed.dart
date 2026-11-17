// The demo build's «Лента» tab (it takes the place of «Рейтинг», which opens from a switch at the
// top), the profile of another person, and the team sheets. Built from the approved mockup
// (docs/PRODUCT_RULES.md, «Лента»). The real app does not use this file.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../screens/rating_screen.dart';
import '../theme/app_colors.dart';
import '../widgets/animated_fire.dart';
import '../widgets/game_icons.dart';
import 'demo_social.dart';
import 'demo_state.dart';

/// The soft colours the owner chose (the green of «Лайм», the lilac of «Мята»).
class _P {
  _P._();
  static bool get _d => AppColors.dark;
  static Color get green => _d ? const Color(0xFF7BDA5E) : const Color(0xFF62C94A);
  static Color get onGreen => _d ? const Color(0xFF10300A) : const Color(0xFF123D0A);
  static Color get greenText => _d ? const Color(0xFF8EE878) : const Color(0xFF3A8A27);
  static Color get greenSoft => _d ? const Color(0x297BDA5E) : const Color(0x3362C94A);
  static Color get lilac => _d ? const Color(0xFF8E97FF) : const Color(0xFF7B85F4);
  static Color get onLilac => _d ? const Color(0xFF0C0E16) : Colors.white;
  static const Color red = Color(0xFFE0454B);
  static const Color gold = Color(0xFFE7B73C);
  static Color get ink => AppColors.primaryDark;
  static Color get muted => AppColors.secondaryText;
  static Color get surface => AppColors.surface;
  static Color get line => AppColors.cardBorder;
  static Color get soft => AppColors.violetSurface;
  static Color get track => AppColors.progressTrack;
}

const _avatarColors = [Color(0xFF5862DD), Color(0xFFE7873C), Color(0xFF2CA58D), Color(0xFFC2477F), Color(0xFF3C8FE7), Color(0xFF8B5CF6), Color(0xFFD14B4B)];

DemoSocial get _s => DemoSocial.instance;

String _fmt(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1).replaceAll('.', ',')}к' : '$n';

class _Av extends StatelessWidget {
  final int id;
  final double size;
  const _Av(this.id, {this.size = 40});

  @override
  Widget build(BuildContext context) {
    final p = _s.people[id];
    final color = id == DemoSocial.me ? _avatarColors[6] : _avatarColors[(p?.color ?? 0) % _avatarColors.length];
    final letter = id == DemoSocial.me ? 'D' : (p?.name ?? '?').substring(0, 1);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(letter, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.38)),
    );
  }
}

/// Avatars overlapping a little, as in «кто поставил лайк».
class _Stack extends StatelessWidget {
  final List<int> ids;
  final double size;
  const _Stack(this.ids, {this.size = 24});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size + (ids.length - 1) * (size - 8),
        height: size,
        child: Stack(children: [
          for (var i = 0; i < ids.length; i++)
            Positioned(
              left: i * (size - 8),
              child: Container(
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _P.surface, width: 2)),
                child: _Av(ids[i], size: size - 4),
              ),
            ),
        ]),
      );
}

BoxDecoration _cardBox() => BoxDecoration(color: _P.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: _P.line));

Widget _section(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
      child: Text(text.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: _P.muted)),
    );

/// The big soft-green button of these screens.
class _GreenButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  const _GreenButton(this.label, {this.icon, this.onTap, super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 50,
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 20),
          label: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          style: FilledButton.styleFrom(
            backgroundColor: _P.green,
            foregroundColor: _P.onGreen,
            disabledBackgroundColor: _P.soft,
            disabledForegroundColor: _P.muted,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      );
}

// =============================================================================================
// The tab

class DemoFeedTab extends StatefulWidget {
  final void Function(int tab) goTo;
  const DemoFeedTab({super.key, required this.goTo});

  @override
  State<DemoFeedTab> createState() => _DemoFeedTabState();
}

class _DemoFeedTabState extends State<DemoFeedTab> {
  bool _rating = false;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: _P.surface, borderRadius: BorderRadius.circular(99), border: Border.all(color: _P.line)),
          child: Row(children: [
            for (final (i, label) in [(0, tr('Лента')), (1, tr('Рейтинг'))])
              Expanded(
                child: GestureDetector(
                  key: ValueKey('feed-switch-$i'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _rating = i == 1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: (i == 1) == _rating ? AppColors.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: (i == 1) == _rating ? Colors.white : _P.muted)),
                  ),
                ),
              ),
          ]),
        ),
      ),
      Expanded(child: _rating ? const RatingScreen() : _FeedList(goTo: widget.goTo)),
    ]);
  }
}

class _FeedList extends StatelessWidget {
  final void Function(int tab) goTo;
  const _FeedList({required this.goTo});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _s.changes,
      builder: (context, _, _) {
        final visible = [for (final c in _s.cards) if (!_s.hiddenCards.contains(c.id)) c];
        final ofFriends = [for (final c in visible) if (_s.isFriend(c.personId)) c];
        final others = [for (final c in visible) if (!_s.isFriend(c.personId)) c];
        return ListView(
          key: const ValueKey('feed-list'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            const _CountCard(),
            if (ofFriends.isNotEmpty) _section(tr('Друзья')),
            for (final c in ofFriends) _FeedCard(c),
            const _Suggestions(),
            _section(tr('Со всего GuYo')),
            for (final c in others.take(2)) _FeedCard(c),
            _TurnCard(goTo: goTo),
            const _TeamsRow(),
            for (final c in others.skip(2)) _FeedCard(c),
          ],
        );
      },
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: _P.lilac, borderRadius: BorderRadius.circular(22)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Сегодня в GuYo выучено'), style: TextStyle(color: _P.onLilac.withValues(alpha: 0.9), fontWeight: FontWeight.w600, fontSize: 13)),
          Text(tr('{0} слов', ['12 480']), style: TextStyle(color: _P.onLilac, fontWeight: FontWeight.w800, fontSize: 32, letterSpacing: -1)),
          Text(tr('Ваш вклад: {0} слов', [DemoState.instance.wordsToday]), style: TextStyle(color: _P.onLilac.withValues(alpha: 0.9), fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
      );
}

class _TurnCard extends StatelessWidget {
  final void Function(int tab) goTo;
  const _TurnCard({required this.goTo});

  @override
  Widget build(BuildContext context) {
    final ds = DemoState.instance;
    final left = (ds.goal - ds.wordsToday).clamp(0, ds.goal);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _P.soft, borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Ваша очередь'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: _P.ink)),
        Text(left > 0 ? tr('До цели дня осталось {0} слов', [left]) : tr('Цель дня выполнена. Ещё урок?'), style: TextStyle(color: _P.muted, fontSize: 13)),
        const SizedBox(height: 10),
        _GreenButton(tr('Начать урок'), key: const ValueKey('feed-start-lesson'), onTap: () => goTo(1)),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// A card

IconData _cardIcon(String kind) => switch (kind) {
      'streak' => Icons.local_fire_department_rounded,
      'rank' => Icons.shield_rounded,
      'duel' => Icons.emoji_events_rounded,
      _ => Icons.star_rounded,
    };

Widget _cardPicture(String kind) => switch (kind) {
      'words' => const PointsIcon(size: 34),
      'gem' => const DiamondIcon(size: 34),
      'streak' => const AnimatedFire(size: 38),
      'duel' => const DuelVsIcon(size: 42),
      _ => Icon(_cardIcon(kind), color: AppColors.primary, size: 32),
    };

class _FeedCard extends StatelessWidget {
  final DemoCard c;
  const _FeedCard(this.c);

  @override
  Widget build(BuildContext context) {
    final person = _s.people[c.personId]!;
    final likers = [if (c.liked) DemoSocial.me, ...c.likers];
    final shown = likers.take(2).map(_s.nameOf).toList();
    final rest = c.likeCount - shown.length;
    final last = c.myComment != null ? (tr('Вы'), c.myComment!) : (_s.nameOf(c.lastComment.$1), c.lastComment.$2);
    return Container(
      key: ValueKey('feed-card-${c.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: _cardBox(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: InkWell(
              key: ValueKey('card-person-${c.id}'),
              onTap: () => openDemoPerson(context, c.personId),
              borderRadius: BorderRadius.circular(12),
              child: Row(children: [
                _Av(c.personId),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(person.name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: _P.ink)),
                    Text(tr(c.when), style: TextStyle(fontSize: 12.5, color: _P.muted)),
                  ]),
                ),
              ]),
            ),
          ),
          IconButton(
            tooltip: tr('Ещё'),
            icon: Icon(Icons.more_horiz_rounded, color: _P.muted),
            onPressed: () => _moreSheet(context, c),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Container(width: 54, height: 54, alignment: Alignment.center, decoration: BoxDecoration(color: _P.soft, borderRadius: BorderRadius.circular(16)), child: _cardPicture(c.icon)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(c.title), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, letterSpacing: -0.3, color: _P.ink)),
              Text(tr(c.subtitle), style: TextStyle(fontSize: 13, color: _P.muted)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _Pill(
            key: ValueKey('like-${c.id}'),
            on: c.liked,
            icon: const Icon(Icons.favorite_rounded, color: _P.red, size: 17),
            text: _fmt(c.likeCount),
            onTap: () {
              HapticFeedback.selectionClick();
              c.liked = !c.liked;
              _s.touch();
            },
          ),
          const SizedBox(width: 6),
          _Pill(
            key: ValueKey('comment-${c.id}'),
            on: false,
            icon: Icon(Icons.chat_bubble_outline_rounded, color: _P.ink, size: 16),
            text: _fmt(c.commentCount),
            onTap: () => _phrasesSheet(context, c),
          ),
        ]),
        const SizedBox(height: 8),
        InkWell(
          key: ValueKey('likers-${c.id}'),
          onTap: () => _likersSheet(context, c),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              _Stack(likers.take(3).toList()),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  rest > 0 ? tr('{0} и ещё {1}', [shown.join(', '), _fmt(rest)]) : shown.join(', '),
                  style: TextStyle(fontSize: 13.5, color: _P.muted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        Text.rich(TextSpan(children: [
          TextSpan(text: '${last.$1}: ', style: TextStyle(fontWeight: FontWeight.w700, color: _P.ink)),
          TextSpan(text: tr(last.$2), style: TextStyle(color: _P.muted)),
        ]), style: const TextStyle(fontSize: 13.5)),
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  final bool on;
  final Widget icon;
  final String text;
  final VoidCallback onTap;
  const _Pill({super.key, required this.on, required this.icon, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: on ? _P.greenSoft : _P.soft,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              icon,
              const SizedBox(width: 6),
              Text(text, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: on ? _P.greenText : _P.ink)),
            ]),
          ),
        ),
      );
}

Future<void> _moreSheet(BuildContext context, DemoCard c) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(Icons.visibility_off_rounded, color: _P.muted),
            title: Text(tr('Скрыть карточку')),
            onTap: () {
              _s.hiddenCards.add(c.id);
              _s.touch();
              Navigator.pop(ctx);
            },
          ),
          ListTile(
            leading: const Icon(Icons.flag_rounded, color: _P.red),
            title: Text(tr('Пожаловаться')),
            onTap: () => Navigator.pop(ctx),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );

Future<void> _phrasesSheet(BuildContext context, DemoCard c) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.canvas,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Комментарий для {0}', [_s.nameOf(c.personId)]), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: _P.ink)),
            const SizedBox(height: 4),
            Text(tr('Выберите готовую фразу. Каждый увидит её на своём языке.'), style: TextStyle(fontSize: 13, color: _P.muted)),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 3.4,
              children: [
                for (final p in DemoSocial.phrases)
                  OutlinedButton(
                    key: ValueKey('phrase-$p'),
                    onPressed: () {
                      c.myComment = p;
                      _s.touch();
                      Navigator.pop(ctx);
                    },
                    style: OutlinedButton.styleFrom(
                      backgroundColor: _P.surface,
                      foregroundColor: _P.ink,
                      side: BorderSide(color: _P.line),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(tr(p), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ]),
        ),
      ),
    );

/// What stands at the right of a person in a list: «Друг», a waiting request, or the green add.
class _Relation extends StatelessWidget {
  final int id;
  const _Relation(this.id);

  @override
  Widget build(BuildContext context) {
    if (id == DemoSocial.me) return const SizedBox.shrink();
    if (_s.isFriend(id)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: _P.greenSoft, borderRadius: BorderRadius.circular(99)),
        child: Text(tr('Друг'), style: TextStyle(color: _P.greenText, fontWeight: FontWeight.w700, fontSize: 12.5)),
      );
    }
    final waiting = _s.friendRequests.contains(id);
    return IconButton(
      key: ValueKey('relation-$id'),
      tooltip: waiting ? tr('Запрос отправлен') : tr('Добавить в друзья'),
      onPressed: () {
        HapticFeedback.selectionClick();
        _s.toggleFriendRequest(id);
      },
      icon: Icon(waiting ? Icons.schedule_rounded : Icons.person_add_alt_1_rounded, color: waiting ? _P.muted : _P.green, size: waiting ? 24 : 28),
    );
  }
}

Future<void> _likersSheet(BuildContext context, DemoCard c) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.canvas,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
        child: ValueListenableBuilder<int>(
          valueListenable: _s.changes,
          builder: (ctx, _, _) {
            final list = [if (c.liked) DemoSocial.me, ...c.likers];
            final more = c.likeCount - list.length;
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                Text(tr('Нравится · {0}', [_fmt(c.likeCount)]), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: _P.ink)),
                const SizedBox(height: 8),
                for (final id in list)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Expanded(
                        child: InkWell(
                          onTap: id == DemoSocial.me ? null : () => openDemoPerson(ctx, id),
                          child: Row(children: [
                            _Av(id),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(_s.nameOf(id), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: _P.ink)),
                                if (id != DemoSocial.me)
                                  Text(
                                    '${_s.isFriend(id) ? '${tr('Друг')} · ' : ''}${tr(_s.people[id]!.rank)} · ${tr('{0} очков', [_s.people[id]!.points])}',
                                    style: TextStyle(fontSize: 12.5, color: _P.muted),
                                  ),
                              ]),
                            ),
                          ]),
                        ),
                      ),
                      _Relation(id),
                    ]),
                  ),
                if (more > 0) Padding(padding: const EdgeInsets.only(top: 6), child: Center(child: Text(tr('и ещё {0}', [_fmt(more)]), style: TextStyle(color: _P.muted, fontSize: 13)))),
              ],
            );
          },
        ),
      ),
    );

// ---------------------------------------------------------------------------------------------
// «Возможно, вы знакомы» and «Команды ищут участников»

class _Suggestions extends StatelessWidget {
  const _Suggestions();

  @override
  Widget build(BuildContext context) {
    final list = [for (final s in _s.suggestions) if (!_s.isFriend(s.$1)) s];
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _section(tr('Возможно, вы знакомы')),
      SizedBox(
        height: 200,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            final (id, why) = list[i];
            final waiting = _s.friendRequests.contains(id);
            return Container(
              width: 150,
              padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
              decoration: BoxDecoration(color: _P.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: _P.line)),
              child: Column(children: [
                InkWell(
                  onTap: () => openDemoPerson(context, id),
                  borderRadius: BorderRadius.circular(12),
                  child: Column(children: [
                    _Av(id, size: 52),
                    const SizedBox(height: 6),
                    Text(_s.nameOf(id), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: _P.ink)),
                  ]),
                ),
                const SizedBox(height: 2),
                Expanded(child: Text(tr(why), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: _P.muted))),
                SizedBox(
                  height: 34,
                  width: double.infinity,
                  child: FilledButton(
                    key: ValueKey('suggest-$id'),
                    onPressed: () => _s.toggleFriendRequest(id),
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: waiting ? _P.soft : _P.green,
                      foregroundColor: waiting ? _P.muted : _P.onGreen,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
                    ),
                    child: Text(waiting ? tr('Запрос отправлен') : tr('Добавить'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                  ),
                ),
              ]),
            );
          },
        ),
      ),
    ]);
  }
}

class _TeamsRow extends StatelessWidget {
  const _TeamsRow();

  @override
  Widget build(BuildContext context) {
    final teams = [for (final t in _s.teams.values) if (!t.members.contains(DemoSocial.me)) t];
    if (teams.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _section(tr('Команды ищут участников')),
      SizedBox(
        height: 150,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: teams.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            final t = teams[i];
            final room = _s.roomIn(t);
            return InkWell(
              key: ValueKey('team-card-${t.id}'),
              onTap: () => showDemoTeamSheet(context, t.id),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 200,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: _P.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: _P.line)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _P.ink)),
                  const SizedBox(height: 8),
                  _Stack(t.members.take(5).toList(), size: 28),
                  const SizedBox(height: 8),
                  Text(room > 0 ? tr('Свободно мест: {0}', [room]) : tr('Мест нет'), style: TextStyle(fontSize: 12.5, color: _P.muted)),
                  const Spacer(),
                  _OpenPill(t.isOpen),
                ]),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 10),
    ]);
  }
}

class _OpenPill extends StatelessWidget {
  final bool open;
  final bool long;
  const _OpenPill(this.open, {this.long = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: open ? _P.greenSoft : _P.soft, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (!open) Icon(Icons.lock_rounded, size: 12, color: _P.muted),
          if (!open) const SizedBox(width: 4),
          Text(
            open ? (long ? tr('Открыта: вступить сразу') : tr('Открыта')) : tr('По заявке'),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: open ? _P.greenText : _P.muted),
          ),
        ]),
      );
}

// =============================================================================================
// Teams: the sheet of one team, the list, a new team

Future<void> showDemoTeamSheet(BuildContext context, int teamId) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.canvas,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
        child: _TeamSheet(teamId),
      ),
    );

class _TeamSheet extends StatefulWidget {
  final int teamId;
  const _TeamSheet(this.teamId);

  @override
  State<_TeamSheet> createState() => _TeamSheetState();
}

class _TeamSheetState extends State<_TeamSheet> {
  String? _error;
  String _name = '';
  bool _goneShown = false;

  /// The team sheet closes and a card says the team is gone (closed by its creator) or that the player left it.
  void _closeWithGone({required bool closed}) {
    final root = Navigator.of(context, rootNavigator: true).context;
    final name = _name;
    Navigator.of(context).pop();
    showDemoTeamGone(root, name: name, closed: closed);
  }

  void _leaveTeam() {
    _goneShown = true; // the team may disappear from under us: the card below is the one message
    try {
      _s.leave();
    } on DemoTeamError catch (e) {
      _goneShown = false;
      setState(() => _error = tr(e.message));
      return;
    }
    _closeWithGone(closed: false);
  }

  void _run(void Function() action) {
    try {
      action();
      setState(() => _error = null);
    } on DemoTeamError catch (e) {
      setState(() => _error = tr(e.message));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _s.changes,
      builder: (context, _, _) {
        final t = _s.teams[widget.teamId];
        if (t == null) {
          // the creator closed the team while this sheet was open
          if (!_goneShown) {
            _goneShown = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _closeWithGone(closed: true);
            });
          }
          return const SizedBox(height: 120);
        }
        _name = t.name;
        final room = _s.roomIn(t);
        final mine = t.members.contains(DemoSocial.me);
        final my = _s.myTeam;
        final owner = _s.nameOf(t.ownerId);
        final requested = _s.teamRequests.contains(t.id);
        Widget note(String text) => Padding(padding: const EdgeInsets.only(top: 6), child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: _P.muted)));
        Widget info(String text) => Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _P.soft, borderRadius: BorderRadius.circular(14)),
              child: Text(text, style: TextStyle(fontSize: 13.5, color: _P.ink)),
            );
        final List<Widget> action;
        if (mine) {
          action = [
            info(tr('Это ваша команда.')),
            TextButton.icon(
              key: const ValueKey('team-leave'),
              onPressed: _leaveTeam,
              icon: const Icon(Icons.logout_rounded, color: _P.red),
              label: Text(tr('Выйти из команды'), style: const TextStyle(color: _P.red, fontWeight: FontWeight.w700)),
            ),
          ];
        } else if (my != null) {
          action = [info(tr('Вы уже в команде «{0}». Чтобы вступить сюда, сначала выйдите из своей.', [my.name]))];
        } else if (room <= 0) {
          action = [_GreenButton(tr('Команда заполнена'))];
        } else if (t.isOpen) {
          action = [_GreenButton(tr('Вступить'), key: const ValueKey('team-join'), onTap: () => _run(() => _s.join(t.id)))];
        } else if (requested) {
          action = [
            SizedBox(
              height: 50,
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const ValueKey('team-request'),
                onPressed: () => _run(() => _s.toggleTeamRequest(t.id)),
                icon: const Icon(Icons.schedule_rounded),
                label: Text(tr('Запрос отправлен'), style: const TextStyle(fontWeight: FontWeight.w800)),
                style: OutlinedButton.styleFrom(foregroundColor: _P.ink, side: BorderSide(color: _P.line), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              ),
            ),
            note(tr('{0} получит уведомление и решит. Нажмите, чтобы отменить.', [owner])),
          ];
        } else {
          action = [
            _GreenButton(tr('Отправить запрос'), key: const ValueKey('team-request'), onTap: () => _run(() => _s.toggleTeamRequest(t.id))),
            note(tr('Решает создатель команды, {0}.', [owner])),
          ];
        }
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Row(children: [
              _TeamIcon(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.name, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: _P.ink)),
                  const SizedBox(height: 4),
                  _OpenPill(t.isOpen, long: true),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _P.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: _P.line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Text(tr('Цель сезона'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: _P.ink)),
                  const Spacer(),
                  Text('${t.seasonGoal}%', style: TextStyle(fontWeight: FontWeight.w700, color: _P.muted)),
                ]),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(value: t.seasonGoal / 100, minHeight: 10, backgroundColor: _P.track, color: _P.lilac),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Text(tr('Участники'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: _P.ink)),
              const Spacer(),
              Text(
                room > 0 ? tr('{0} из {1} · свободно {2}', [t.members.length, DemoSocial.capacity, room]) : tr('{0} из {1}', [t.members.length, DemoSocial.capacity]),
                style: TextStyle(color: _P.muted, fontSize: 12.5),
              ),
            ]),
            const SizedBox(height: 6),
            for (final m in t.members)
              InkWell(
                onTap: m == DemoSocial.me ? null : () => openDemoPerson(context, m),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    _Av(m, size: 34),
                    const SizedBox(width: 10),
                    Text(_s.nameOf(m), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: _P.ink)),
                    if (m == t.ownerId) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.workspace_premium_rounded, size: 16, color: _P.gold)),
                    const Spacer(),
                    Text(
                      m == t.ownerId ? tr('создатель') : (m == DemoSocial.me ? '' : tr('{0} очков', [_s.people[m]?.points ?? 0])),
                      style: TextStyle(fontSize: 12.5, color: _P.muted),
                    ),
                  ]),
                ),
              ),
            const SizedBox(height: 12),
            ...action,
            if (_error != null) note(_error!),
          ],
        );
      },
    );
  }
}

class _TeamIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: _P.soft, borderRadius: BorderRadius.circular(14)),
        child: Icon(Icons.groups_rounded, color: AppColors.primary),
      );
}

/// The card in the middle of the screen when a team is gone: closed by its creator, or the player left it.
Future<void> showDemoTeamGone(BuildContext context, {required String name, required bool closed}) => showDialog<void>(
      context: context,
      barrierColor: const Color(0x8C05070E),
      builder: (ctx) => Dialog(
        key: const ValueKey('team-gone'),
        backgroundColor: _P.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26), side: BorderSide(color: _P.line)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(color: _P.soft, borderRadius: BorderRadius.circular(20)),
              child: Icon(Icons.group_off_rounded, size: 32, color: _P.lilac),
            ),
            const SizedBox(height: 14),
            Text(closed ? tr('Команды «{0}» больше нет', [name]) : tr('Вы вышли из команды «{0}»', [name]), textAlign: TextAlign.center, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: _P.ink)),
            const SizedBox(height: 8),
            Text(
              closed ? tr('Создатель закрыл её. Ваши очки и серия остались с вами, можно найти новую команду.') : tr('Ваши очки и серия остались с вами. Можно найти другую команду или создать свою.'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.4, color: _P.muted),
            ),
            const SizedBox(height: 18),
            _GreenButton(tr('Найти команду'), key: const ValueKey('team-gone-find'), onTap: () {
              Navigator.of(ctx).pop();
              showDemoTeamsList(context);
            }),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton(
                key: const ValueKey('team-gone-create'),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  showDemoCreateTeam(context);
                },
                style: OutlinedButton.styleFrom(foregroundColor: _P.muted, side: BorderSide(color: _P.line, width: 1.5), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                child: Text(tr('Создать свою'), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ),
      ),
    );

Future<void> showDemoTeamsList(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.canvas,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
        child: ValueListenableBuilder<int>(
          valueListenable: _s.changes,
          builder: (ctx, _, _) => ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text(tr('Найти команду'), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: _P.ink)),
              const SizedBox(height: 4),
              Text(tr('Открытые принимают сразу, в остальные отправляется запрос создателю.'), style: TextStyle(fontSize: 13, color: _P.muted)),
              const SizedBox(height: 10),
              for (final t in _s.teams.values)
                if (!t.members.contains(DemoSocial.me))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: _P.surface,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        key: ValueKey('teams-list-${t.id}'),
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => showDemoTeamSheet(ctx, t.id),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(children: [
                            _TeamIcon(),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(t.name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: _P.ink)),
                                Text(
                                  '${_s.roomIn(t) > 0 ? tr('свободно {0}', [_s.roomIn(t)]) : tr('мест нет')} · ${t.isOpen ? tr('открыта') : tr('по заявке')}',
                                  style: TextStyle(fontSize: 12.5, color: _P.muted),
                                ),
                              ]),
                            ),
                            Icon(Icons.chevron_right_rounded, color: _P.muted),
                          ]),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );

Future<void> showDemoCreateTeam(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.canvas,
      builder: (ctx) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom), child: const _CreateTeam()),
    );

class _CreateTeam extends StatefulWidget {
  const _CreateTeam();

  @override
  State<_CreateTeam> createState() => _CreateTeamState();
}

class _CreateTeamState extends State<_CreateTeam> {
  final _name = TextEditingController();
  bool _open = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _name.text.trim().length >= 3;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Новая команда'), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: _P.ink)),
          const SizedBox(height: 4),
          Text(tr('Название от 3 до 24 символов. До {0} человек.', [DemoSocial.capacity]), style: TextStyle(fontSize: 13, color: _P.muted)),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('team-name'),
            controller: _name,
            maxLength: 24,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: tr('Название команды'),
              filled: true,
              fillColor: _P.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: _P.line)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: _P.line)),
            ),
          ),
          Material(
            color: _P.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: _P.line)),
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              key: const ValueKey('team-open'),
              value: _open,
              onChanged: (v) => setState(() => _open = v),
              activeThumbColor: Colors.white,
              activeTrackColor: _P.green,
              title: Text(tr('Открыта для вступления'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: _P.ink)),
              subtitle: Text(_open ? tr('Любой вступит сразу, пока есть места') : tr('Вступают по запросу, решаете вы'), style: TextStyle(fontSize: 12.5, color: _P.muted)),
            ),
          ),
          const SizedBox(height: 12),
          _GreenButton(
            tr('Создать команду'),
            key: const ValueKey('team-create'),
            onTap: !valid
                ? null
                : () {
                    try {
                      _s.create(_name.text, isOpen: _open);
                      Navigator.pop(context);
                    } on DemoTeamError catch (e) {
                      setState(() => _error = tr(e.message));
                    }
                  },
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: _P.red))),
        ]),
      ),
    );
  }
}

/// The player's own profile: their team, or how to find or make one.
class DemoMyTeamCard extends StatelessWidget {
  const DemoMyTeamCard({super.key});

  static const _gradient = [Color(0xFF14B8A6), Color(0xFF2563EB)];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _s.changes,
      builder: (context, _, _) {
        final t = _s.myTeam;
        if (t != null) {
          return Container(
            key: const ValueKey('my-team-card'),
            padding: const EdgeInsets.all(14),
            decoration: _cardBox(),
            child: InkWell(
              onTap: () => showDemoTeamSheet(context, t.id),
              child: Row(children: [
                _TeamIcon(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('Команда «{0}»', [t.name]), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _P.ink)),
                    Text('${tr('{0} из {1}', [t.members.length, DemoSocial.capacity])} · ${t.isOpen ? tr('открыта') : tr('по заявке')}', style: TextStyle(fontSize: 12.5, color: _P.muted)),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: _P.muted),
              ]),
            ),
          );
        }
        // no team yet: the same blue card as inside the season pass («Играйте вместе»), a little smaller
        return Container(
          key: const ValueKey('my-team-card'),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: _gradient),
            boxShadow: [BoxShadow(color: _gradient.last.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 7))],
          ),
          child: Column(children: [
            const Icon(Icons.groups_rounded, size: 44, color: Colors.white),
            const SizedBox(height: 4),
            Text(tr('Играйте вместе'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Colors.white)),
            const SizedBox(height: 4),
            Text(
              tr('Соберите команду из друзей: общие цели недели и сезона, бонусная энергия и командный значок'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, height: 1.3, color: Colors.white.withValues(alpha: 0.9)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton(
                key: const ValueKey('my-team-create'),
                onPressed: () => showDemoCreateTeam(context),
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: _gradient.last),
                child: Text(tr('Создать команду'), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton(
                key: const ValueKey('my-team-find'),
                onPressed: () => showDemoTeamsList(context),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white, width: 1.5)),
                child: Text(tr('Найти команду'), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        );
      },
    );
  }
}

// =============================================================================================
// Another person's profile (variant C of the mockup, without the number tiles, the title and the status)

Future<void> openDemoPerson(BuildContext context, int id) {
  if (id == DemoSocial.me) return Future.value();
  return Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DemoPersonScreen(id)));
}

class DemoPersonScreen extends StatefulWidget {
  final int id;
  const DemoPersonScreen(this.id, {super.key});

  @override
  State<DemoPersonScreen> createState() => _DemoPersonScreenState();
}

class _DemoPersonScreenState extends State<DemoPersonScreen> {
  bool _duelSent = false;

  @override
  Widget build(BuildContext context) {
    final p = _s.people[widget.id]!;
    return ValueListenableBuilder<int>(
      valueListenable: _s.changes,
      builder: (context, _, _) {
        final team = _s.teamOf(p.id);
        final friend = _s.isFriend(p.id);
        final waiting = _s.friendRequests.contains(p.id);
        return Scaffold(
          backgroundColor: AppColors.canvas,
          appBar: AppBar(
            backgroundColor: AppColors.canvas,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            actions: [IconButton(tooltip: tr('Ещё'), icon: Icon(Icons.more_horiz_rounded, color: _P.muted), onPressed: () {})],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
                decoration: BoxDecoration(color: _P.lilac, borderRadius: BorderRadius.circular(24)),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: _P.gold),
                    child: _Av(p.id, size: 80),
                  ),
                  const SizedBox(height: 10),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(p.name, style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: _P.onLilac)),
                    const SizedBox(width: 6),
                    const PremiumIcon(size: 20),
                  ]),
                ]),
              ),
              const SizedBox(height: 12),
              _Achievements(p.achievements),
              if (team != null) ...[
                const SizedBox(height: 12),
                Container(
                  decoration: _cardBox(),
                  child: InkWell(
                    key: const ValueKey('person-team'),
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => showDemoTeamSheet(context, team.id),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        _TeamIcon(),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(tr('Команда «{0}»', [team.name]), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _P.ink)),
                            Text('${tr('{0} из {1}', [team.members.length, DemoSocial.capacity])} · ${team.isOpen ? tr('открыта') : tr('по заявке')}', style: TextStyle(fontSize: 12.5, color: _P.muted)),
                          ]),
                        ),
                        Icon(Icons.chevron_right_rounded, color: _P.muted),
                      ]),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _WeekPoints(p.week),
              const SizedBox(height: 12),
              _Habits(p),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              decoration: BoxDecoration(color: AppColors.canvas, border: Border(top: BorderSide(color: _P.line))),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (friend) ...[
                  SizedBox(
                    height: 50,
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const ValueKey('person-duel'),
                      onPressed: _duelSent ? null : () => setState(() => _duelSent = true),
                      icon: const DuelIcon(size: 26),
                      label: Text(_duelSent ? tr('Вызов отправлен') : tr('Вызвать на дуэль'), style: const TextStyle(fontWeight: FontWeight.w800)),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    ),
                  ),
                  TextButton.icon(
                    key: const ValueKey('person-unfriend'),
                    onPressed: () => _s.removeFriend(p.id),
                    icon: const Icon(Icons.person_remove_rounded, color: _P.red),
                    label: Text(tr('Удалить из друзей'), style: const TextStyle(color: _P.red, fontWeight: FontWeight.w700)),
                  ),
                ] else if (waiting)
                  SizedBox(
                    height: 50,
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const ValueKey('person-add'),
                      onPressed: () => _s.toggleFriendRequest(p.id),
                      icon: const Icon(Icons.schedule_rounded),
                      label: Text(tr('Запрос отправлен'), style: const TextStyle(fontWeight: FontWeight.w800)),
                      style: OutlinedButton.styleFrom(foregroundColor: _P.ink, side: BorderSide(color: _P.line), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    ),
                  )
                else
                  _GreenButton(tr('Добавить в друзья'), key: const ValueKey('person-add'), icon: Icons.person_add_alt_1_rounded, onTap: () => _s.toggleFriendRequest(p.id)),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _Achievements extends StatelessWidget {
  final int earned;
  const _Achievements(this.earned);

  @override
  Widget build(BuildContext context) {
    final pics = <Widget>[
      const AnimatedFire(size: 32),
      const DiamondIcon(size: 30),
      const Icon(Icons.star_border_rounded, color: _P.gold, size: 30),
      const PointsIcon(size: 30),
      const DuelVsIcon(size: 34),
      Icon(Icons.menu_book_rounded, color: AppColors.primary, size: 28),
    ];
    final on = earned.clamp(0, 6);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardBox(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text(tr('Достижения'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: _P.ink)),
          const Spacer(),
          Text(tr('{0} из {1}', [earned, 20]), style: TextStyle(fontSize: 12.5, color: _P.muted)),
        ]),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (var i = 0; i < 8; i++)
              Opacity(
                opacity: i < on ? 1 : 0.55,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: i < on ? _P.soft : _P.track, borderRadius: BorderRadius.circular(16)),
                  child: i < on ? pics[i] : Icon(Icons.lock_outline_rounded, color: _P.muted),
                ),
              ),
          ],
        ),
      ]),
    );
  }
}

class _WeekPoints extends StatelessWidget {
  final List<int> week;
  const _WeekPoints(this.week);

  @override
  Widget build(BuildContext context) {
    final days = [tr('Пн'), tr('Вт'), tr('Ср'), tr('Чт'), tr('Пт'), tr('Сб'), tr('Вс')];
    final max = week.reduce((a, b) => a > b ? a : b);
    final best = week.indexOf(max);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardBox(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text(tr('Очки за неделю'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: _P.ink)),
          const Spacer(),
          Text(tr('{0} всего', [week.fold<int>(0, (a, b) => a + b)]), style: TextStyle(fontSize: 12.5, color: _P.muted)),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Tooltip(
                  message: '${days[i]}: ${tr('{0} очков', [week[i]])}',
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    if (i == best) Text('${week[i]}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: _P.ink)),
                    const SizedBox(height: 4),
                    Container(
                      width: 26,
                      height: max == 0 || week[i] == 0 ? 3 : (week[i] / max * 80).clamp(6, 80).toDouble(),
                      decoration: BoxDecoration(color: week[i] == 0 ? _P.line : _P.green, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                    ),
                    const SizedBox(height: 4),
                    Text(days[i], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _P.muted)),
                  ]),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _Habits extends StatelessWidget {
  final DemoPerson p;
  const _Habits(this.p);

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String title, String sub) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 14, color: _P.ink)),
                Text(sub, style: TextStyle(fontSize: 12.5, color: _P.muted)),
              ]),
            ),
          ]),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: _cardBox(),
      child: Column(children: [
        row(Icons.schedule_rounded, tr('Обычно занимается'), p.hours),
        Divider(height: 1, color: _P.line),
        row(Icons.calendar_today_rounded, tr('Лучший день'), tr(p.bestDay)),
        Divider(height: 1, color: _P.line),
        row(Icons.track_changes_rounded, tr('Точность {0}%', [p.accuracy]), tr('в среднем {0} с на ответ', [p.avgAnswer])),
        Divider(height: 1, color: _P.line),
        row(Icons.menu_book_rounded, tr('Изучает: {0}', [tr('Английский')]), tr('темы: {0}', [tr('Еда, Путешествия')])),
      ]),
    );
  }
}
