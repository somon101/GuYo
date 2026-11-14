import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../models/chest.dart';
import '../services/chest_queue.dart';
import '../models/reward_spec.dart';
import '../widgets/reward_claim_effect.dart';
import '../widgets/game_icons.dart';
import 'chest_open_screen.dart';

/// "Мои сундуки": everything the person has, by kind. Each kind has one green
/// "Открыть" button; ×5 appears from 5 chests and ×10 from 10. Only one kind is
/// opened at a time, and fewer than 5 chests are opened one by one.
class ChestListScreen extends StatefulWidget {
  final ChestBank bank;

  /// The tickets to start from (tests); otherwise the remembered ones.
  final BoosterState? initialBoosters;
  const ChestListScreen({super.key, required this.bank, this.initialBoosters});

  @override
  State<ChestListScreen> createState() => _ChestListScreenState();
}

class _ChestListScreenState extends State<ChestListScreen> {
  late ChestBank _bank = widget.bank;
  final Map<String, int> _mode = {};
  bool _busy = false;
  late BoosterState? _boosters = widget.initialBoosters ?? ApiClient.instance.cachedBoosters();
  Timer? _tick;
  String? _notice;
  Timer? _noticeTimer;

  @override
  void initState() {
    super.initState();
    // A system toast left over from another screen must not hang over this one.
    WidgetsBinding.instance.addPostFrameCallback((_) => ScaffoldMessenger.maybeOf(context)?.clearSnackBars());
    _loadBoosters();
    _refresh();
    ChestQueue.correction.addListener(_onCorrection);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ['chest', 'rating', 'xp'].any((k) => _boosters?.of(k).running ?? false)) setState(() {});
    });
  }

  @override
  void dispose() {
    ChestQueue.correction.removeListener(_onCorrection);
    _tick?.cancel();
    _noticeTimer?.cancel();
    super.dispose();
  }

  /// What the server has right now (the list is opened from a remembered copy, which can be old).
  Future<void> _refresh() async {
    await ChestQueue.flush();
    final fresh = await ApiClient.instance.fetchChests();
    if (fresh != null && mounted) setState(() => _bank = fresh);
  }

  Future<void> _loadBoosters() async {
    final b = await ApiClient.instance.fetchBoosters();
    if (mounted && b != null) setState(() => _boosters = b);
  }

  /// «Включить»: switches a ticket on, with the effect, then refreshes the bank (the prizes of
  /// the chests opened from now on are doubled).
  Future<void> _activate(int minutes, [String kind = 'chest']) async {
    try {
      final b = await ApiClient.instance.activateBooster(minutes, kind: kind);
      if (!mounted) return;
      setState(() => _boosters = b);
      await showRewardClaimEffect(context, title: kind == 'rating' ? tr('Очки рейтинга ×2') : kind == 'xp' ? tr('Энергия пропуска ×2') : tr('Награды ×2'), rewards: [RewardSpec(type: 'booster', amount: minutes, kind: kind)]);
      final fresh = await ApiClient.instance.fetchChests();
      if (fresh != null && mounted) setState(() => _bank = fresh);
    } on ApiException catch (e) {
      if (mounted) _say(e.message);
    } catch (_) {
      if (mounted) _say(tr('Не удалось. Проверьте интернет.'));
    }
  }

  void _onCorrection() {
    final m = ChestQueue.correction.value;
    if (m != null && mounted) {
      ChestQueue.correction.value = null;
      _say(m);
    }
  }

  void _say(String message) {
    _noticeTimer?.cancel();
    setState(() => _notice = message);
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  int _count(String key) => _bank.chests.where((c) => c.chestKey == key).length;

  /// The multiplier actually in force: the chosen one, lowered while there are too few chests.
  int _multiplier(String key) {
    final n = _count(key);
    final chosen = _mode[key] ?? 1;
    if (chosen >= 10 && n >= 10) return 10;
    if (chosen >= 5 && n >= 5) return 5;
    return 1;
  }

  Future<void> _open(String key) async {
    if (_busy) return;
    final m = _multiplier(key);
    _busy = true;
    ChestBank? result;
    try {
      result = await Navigator.of(context).push<ChestBank>(
        MaterialPageRoute(builder: (_) => ChestOpenScreen(bank: _bank, chests: [for (final c in _bank.chests) if (c.chestKey == key) c].take(m).toList())),
      );
    } finally {
      // The buttons are live again the moment the opening screen is closed.
      _busy = false;
    }
    if (result != null && mounted) setState(() => _bank = result!);
    // The server catch-up happens quietly in the background.
    // ignore: unawaited_futures
    _refresh();
  }

  Future<void> _claim() async {
    try {
      final bank = await ApiClient.instance.claimDailyChest();
      if (mounted) setState(() => _bank = bank);
    } on ApiException catch (e) {
      if (mounted) _say(e.message);
      // e.g. "already taken": the list was out of date, show what the server has
      await _refresh();
    } catch (_) {
      if (mounted) _say(tr('Не удалось. Проверьте интернет.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final daily = _bank.daily;
    final total = _bank.chests.length;
    final hasBoosters = _boosters != null && ['chest', 'rating', 'xp'].any((k) => _boosters!.of(k).total > 0 || _boosters!.of(k).running);
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: BackButton(key: const ValueKey('chest-list-back'), color: AppColors.primaryDark, onPressed: () => Navigator.of(context).pop(_bank)),
        title: Text('${tr('Мои сундуки')} · $total', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (_notice != null)
            Container(
              key: const ValueKey('chest-notice'),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: AppColors.violetSurface, borderRadius: BorderRadius.circular(12)),
              child: Text(_notice!, style: TextStyle(color: AppColors.primaryDark, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          if (daily.enabled && !daily.claimed) _dailyTile(daily),
          _groupTitle(tr('Сундуки')),
          Container(
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (var i = 0; i < _bank.types.length; i++) ...[
                if (i > 0) _hairline(),
                _row(_bank.types[i]),
              ],
            ]),
          ),
          if (total == 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(tr('Пока сундуков нет'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.secondaryText)),
            ),
          if (hasBoosters) ...[
            const SizedBox(height: 18),
            _groupTitle(tr('Бонусы')),
            _boostersTile(_boosters!),
          ],
        ],
      ),
    );
  }

  Widget _groupTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
        child: Text(text.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: AppColors.secondaryText)),
      );

  Widget _hairline() => Divider(height: 1, thickness: 1, indent: 14, endIndent: 0, color: AppColors.cardBorder);

  String _left(DateTime until) {
    final s = until.difference(DateTime.now()).inSeconds.clamp(0, 1 << 30);
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
  }

  static const _kindNames = {'chest': 'Удвоитель сундуков', 'rating': 'Удвоитель рейтинга', 'xp': 'Удвоитель пропуска'};
  static const _kindHints = {
    'chest': 'Призы из сундуков удваиваются, пока идёт время.',
    'rating': 'Все очки рейтинга удваиваются, пока идёт время.',
    'xp': 'Вся энергия пропуска удваивается, пока идёт время.',
  };

  String? _boostTab;

  /// A segmented switch: [labels] in a quiet track, the chosen one lifted onto the surface.
  Widget _segment<T>({required List<T> values, required T selected, required Widget Function(T) label, required void Function(T) onTap, required Key Function(T) keyOf, bool expand = false}) {
    final items = [
      for (final v in values)
        GestureDetector(
          key: keyOf(v),
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap(v),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: v == selected ? AppColors.surface : null, borderRadius: BorderRadius.circular(8)),
            child: label(v),
          ),
        ),
    ];
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: AppColors.violetSurface, borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, children: [for (final i in items) expand ? Expanded(child: i) : i]),
    );
  }

  /// «Бонусы»: a switch between the three kinds (each shows its timer or how many are held), a line
  /// on what it does and the tickets held, one per row.
  Widget _boostersTile(BoosterState all) {
    final kinds = [for (final k in const ['chest', 'rating', 'xp']) if (all.of(k).total > 0 || all.of(k).running) k];
    if (kinds.isEmpty) return const SizedBox.shrink();
    final tab = kinds.contains(_boostTab) ? _boostTab! : kinds.first;
    final b = all.of(tab);
    final held = [for (final e in b.items.entries) if (e.value > 0) e];
    return Container(
      key: const ValueKey('boosters-tile'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _segment<String>(
          values: kinds,
          selected: tab,
          expand: true,
          keyOf: (k) => ValueKey('boost-tab-$k'),
          onTap: (k) => setState(() => _boostTab = k),
          label: (k) => Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            BoosterIcon(size: 22, kind: k),
            const SizedBox(width: 5),
            all.of(k).running
                ? Text(_left(all.of(k).activeUntil!), key: ValueKey('boost-running-$k'), style: TextStyle(color: AppColors.primary, fontSize: 12.5, fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()]))
                : Text('${all.of(k).total}', style: TextStyle(color: AppColors.primaryDark, fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
        ),
        const SizedBox(height: 12),
        Text(tr(_kindNames[tab]!), style: TextStyle(color: AppColors.primaryDark, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(b.running ? tr('Идёт удвоение. Ещё один билет прибавит время.') : tr(_kindHints[tab]!), style: TextStyle(color: AppColors.secondaryText, fontSize: 12.5)),
        const SizedBox(height: 6),
        if (held.isEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr('Билетов нет'), style: TextStyle(color: AppColors.secondaryText, fontSize: 13)))
        else
          for (final e in held) ...[
            Divider(height: 1, thickness: 1, color: AppColors.cardBorder),
            SizedBox(
              height: 52,
              child: Row(children: [
                Text(_minutesLabel(e.key), style: TextStyle(color: AppColors.primaryDark, fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(width: 10),
                Text('×${e.value}', style: TextStyle(color: AppColors.secondaryText, fontSize: 14, fontFeatures: const [FontFeature.tabularFigures()])),
                const Spacer(),
                GestureDetector(
                  key: ValueKey('boost-on-$tab-${e.key}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _activate(e.key, tab),
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12), child: Text(tr('Включить'), style: TextStyle(color: AppColors.primary, fontSize: 15, fontWeight: FontWeight.w700))),
                ),
              ]),
            ),
          ],
      ]),
    );
  }

  String _minutesLabel(int m) => m >= 60 && m % 60 == 0 ? tr('{0} ч', [m ~/ 60]) : tr('{0} мин', [m]);

  /// «Сундук дня»: one plain line, the name on the left and «Забрать» as a text link on the right.
  Widget _dailyTile(DailyChest daily) => Container(
        key: const ValueKey('daily-tile'),
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(children: [
          Opacity(opacity: daily.available ? 1 : 0.5, child: ChestImage(daily.chestKey, size: 34)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Сундук дня'), style: TextStyle(color: AppColors.primaryDark, fontSize: 16, fontWeight: FontWeight.w700)),
              if (!daily.available) Text(daily.conditions, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.secondaryText, fontSize: 12.5)),
            ]),
          ),
          if (daily.available)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _claim,
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10), child: Text(tr('Забрать'), style: TextStyle(color: AppColors.primary, fontSize: 16, fontWeight: FontWeight.w700))),
            ),
        ]),
      );

  /// One chest kind: its picture, name and number; when some are held, «Открыть» (and ×5 / ×10 once
  /// there are enough).
  Widget _row(ChestType t) {
    final n = _count(t.key);
    final m = _multiplier(t.key);
    final options = [1, 5, 10].where((x) => x == 1 || n >= x).toList();
    final openLabel = m > 1 ? '${tr('Открыть')} ×$m' : tr('Открыть');
    return Opacity(
      opacity: n == 0 ? 0.45 : 1,
      child: Padding(
        key: ValueKey('chest-row-${t.key}'),
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
        child: Column(children: [
          SizedBox(
            height: 60,
            child: Row(children: [
              ChestImage(t.key, size: 40),
              const SizedBox(width: 12),
              Expanded(child: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.primaryDark, fontSize: 15.5, fontWeight: FontWeight.w600))),
              Text('$n', style: TextStyle(color: AppColors.primaryDark, fontSize: 16, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
              if (n > 0 && options.length == 1) ...[
                const SizedBox(width: 14),
                GestureDetector(
                  key: ValueKey('open-${t.key}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _busy ? null : () => _open(t.key),
                  child: Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(openLabel, style: TextStyle(color: AppColors.primary, fontSize: 15, fontWeight: FontWeight.w700))),
                ),
              ],
            ]),
          ),
          if (n > 0 && options.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                _segment<int>(values: options, selected: m, keyOf: (x) => ValueKey('mode-${t.key}-$x'), onTap: (x) => setState(() => _mode[t.key] = x), label: (x) => Text('×$x', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: m == x ? AppColors.primaryDark : AppColors.secondaryText))),
                const Spacer(),
                GestureDetector(
                  key: ValueKey('open-${t.key}'),
                  onTap: _busy ? null : () => _open(t.key),
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(99)),
                    child: Text(openLabel, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// The ticket with the number held, on a corner plate (like the chests).
class CountedBoosterIcon extends StatelessWidget {
  final int count;
  final String kind;
  const CountedBoosterIcon({super.key, required this.count, this.kind = 'chest'});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 52,
        height: 52,
        child: Stack(clipBehavior: Clip.none, children: [
          BoosterIcon(size: 52, kind: kind),
          Positioned(
            left: 52 * 0.8,
            top: 52 * 0.76,
            child: FractionalTranslation(
              translation: const Offset(-0.5, -0.5),
              child: Container(
                constraints: const BoxConstraints(minWidth: 22),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0xFF1B1247), borderRadius: BorderRadius.circular(99), boxShadow: const [BoxShadow(color: Color(0xFFFFC928), spreadRadius: 2)]),
                child: Text('$count', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12, height: 1)),
              ),
            ),
          ),
        ]),
      );
}
