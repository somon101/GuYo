import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/chest.dart';
import '../services/chest_queue.dart';
import '../models/reward_spec.dart';
import '../widgets/counted_chest.dart';
import '../widgets/reward_claim_effect.dart';
import '../widgets/game_icons.dart';
import 'chest_open_screen.dart';

/// "Мои сундуки": everything the person has, by kind. Each kind has one green
/// "Открыть" button; ×5 appears from 5 chests and ×10 from 10. Only one kind is
/// opened at a time, and fewer than 5 chests are opened one by one.
class ChestListScreen extends StatefulWidget {
  final ChestBank bank;
  const ChestListScreen({super.key, required this.bank});

  @override
  State<ChestListScreen> createState() => _ChestListScreenState();
}

class _ChestListScreenState extends State<ChestListScreen> {
  late ChestBank _bank = widget.bank;
  final Map<String, int> _mode = {};
  bool _busy = false;
  BoosterState? _boosters = ApiClient.instance.cachedBoosters();
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
      if (mounted && (_boosters?.running ?? false)) setState(() {});
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
  Future<void> _activate(int minutes) async {
    try {
      final b = await ApiClient.instance.activateBooster(minutes);
      if (!mounted) return;
      setState(() => _boosters = b);
      await showRewardClaimEffect(context, title: tr('Награды ×2'), rewards: [RewardSpec(type: 'booster', amount: minutes)]);
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
    try {
      final result = await Navigator.of(context).push<ChestBank>(
        MaterialPageRoute(builder: (_) => ChestOpenScreen(bank: _bank, chests: [for (final c in _bank.chests) if (c.chestKey == key) c].take(m).toList())),
      );
      if (result != null && mounted) setState(() => _bank = result);
      await ChestQueue.flush();
      final fresh = await ApiClient.instance.fetchChests();
      if (fresh != null && mounted) setState(() => _bank = fresh);
    } finally {
      _busy = false;
    }
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
    return Scaffold(
      backgroundColor: const Color(0xFF1E1560),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: BackButton(key: const ValueKey('chest-list-back'), onPressed: () => Navigator.of(context).pop(_bank)),
        title: Text('${tr('Мои сундуки')} · $total', style: const TextStyle(fontWeight: FontWeight.w900)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (_notice != null)
            Container(
              key: const ValueKey('chest-notice'),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: const Color(0x33FFB020), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0x80FFB020))),
              child: Text(_notice!, style: const TextStyle(color: Color(0xFFFFD27A), fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          if (_boosters != null && (_boosters!.total > 0 || _boosters!.running)) _boostersTile(_boosters!),
          if (daily.enabled && !daily.claimed) _dailyTile(daily),
          for (final t in _bank.types) _row(t),
          if (total == 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(tr('Пока сундуков нет'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            ),
        ],
      ),
    );
  }

  String _left(DateTime until) {
    final s = until.difference(DateTime.now()).inSeconds.clamp(0, 1 << 30);
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
  }

  Widget _boostersTile(BoosterState b) => Container(
        key: const ValueKey('boosters-tile'),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(tr('Мои бонусы'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900))),
            if (b.running)
              Container(
                key: const ValueKey('boost-running'),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(99), border: Border.all(color: const Color(0xFFFFD54F), width: 1.5)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const BoosterIcon(size: 22),
                  const SizedBox(width: 4),
                  Text(_left(b.activeUntil!), style: const TextStyle(color: Color(0xFFFFD54F), fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()])),
                ]),
              ),
          ]),
          const SizedBox(height: 4),
          Text(
            b.running ? tr('Идёт удвоение. Ещё один билет прибавит время.') : tr('Включите билет, чтобы призы из сундуков удваивались, пока идёт время.'),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 8),
          for (final e in b.items.entries)
            Opacity(
              opacity: e.value > 0 ? 1 : 0.45,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  CountedBoosterIcon(count: e.value),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_minutesLabel(e.key), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
                  GreenButton(key: ValueKey('boost-on-${e.key}'), label: tr('Включить'), onTap: e.value > 0 ? () => _activate(e.key) : null, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                ]),
              ),
            ),
        ]),
      );

  String _minutesLabel(int m) => m >= 60 && m % 60 == 0 ? tr('{0} ч', [m ~/ 60]) : tr('{0} мин', [m]);

  Widget _dailyTile(DailyChest daily) => Container(
        key: const ValueKey('daily-tile'),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Opacity(opacity: daily.available ? 1 : 0.5, child: ChestImage(daily.chestKey, size: 54)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Сундук дня'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(daily.available ? tr('Нажмите, чтобы забрать') : daily.conditions, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
          if (daily.available) GreenButton(label: tr('Забрать'), onTap: _claim),
        ]),
      );

  Widget _row(ChestType t) {
    final n = _count(t.key);
    final m = _multiplier(t.key);
    final options = [1, 5, 10].where((x) => x == 1 || n >= x).toList();
    return Opacity(
      opacity: n == 0 ? 0.5 : 1,
      child: Container(
        key: ValueKey('chest-row-${t.key}'),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          Row(children: [
            CountedChest(chestKey: t.key, color: Color(t.color), count: n, size: 60),
            const SizedBox(width: 14),
            Expanded(child: Text(t.name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
          if (n > 0) ...[
            const SizedBox(height: 10),
            Row(children: [
              if (options.length > 1)
                for (final x in options)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      key: ValueKey('mode-${t.key}-$x'),
                      onTap: () => setState(() => _mode[t.key] = x),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: m == x ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFE56B), Color(0xFFFFAB1A)]) : null,
                          color: m == x ? null : Colors.white.withValues(alpha: 0.14),
                          boxShadow: m == x ? const [BoxShadow(color: Color(0xFFB36A00), offset: Offset(0, 2))] : null,
                        ),
                        child: Text('×$x', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: m == x ? const Color(0xFF4A2A00) : Colors.white70)),
                      ),
                    ),
                  ),
              Expanded(
                child: GreenButton(key: ValueKey('open-${t.key}'), label: m > 1 ? '${tr('Открыть')} ×$m' : tr('Открыть'), onTap: _busy ? null : () => _open(t.key)),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}

/// The ticket with the number held, on a corner plate (like the chests).
class CountedBoosterIcon extends StatelessWidget {
  final int count;
  const CountedBoosterIcon({super.key, required this.count});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 52,
        height: 52,
        child: Stack(clipBehavior: Clip.none, children: [
          const BoosterIcon(size: 52),
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
