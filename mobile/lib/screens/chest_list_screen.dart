import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/chest.dart';
import '../widgets/counted_chest.dart';
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
  String? _notice;
  Timer? _noticeTimer;

  @override
  void initState() {
    super.initState();
    // A system toast left over from another screen must not hang over this one.
    WidgetsBinding.instance.addPostFrameCallback((_) => ScaffoldMessenger.maybeOf(context)?.clearSnackBars());
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    super.dispose();
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
        MaterialPageRoute(builder: (_) => ChestOpenScreen(bank: _bank, chestKey: key, count: m)),
      );
      if (result != null && mounted) setState(() => _bank = result);
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
              if (_notice != null)
                Container(
                  key: const ValueKey('chest-notice'),
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0x33FFB020), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0x80FFB020))),
                  child: Text(_notice!, style: const TextStyle(color: Color(0xFFFFD27A), fontSize: 12, fontWeight: FontWeight.w700)),
                ),
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
