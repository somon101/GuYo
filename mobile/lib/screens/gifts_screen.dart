import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/chest.dart';
import '../models/notification.dart';
import '../models/reward_spec.dart';
import '../services/chest_queue.dart';
import '../services/streak_state.dart';
import '../theme/app_colors.dart';
import '../widgets/flat_green_button.dart';
import '../widgets/game_icons.dart';
import '../widgets/gift_badge.dart';
import '../widgets/reward_chips.dart';
import '../widgets/reward_claim_effect.dart';
import 'chest_open_screen.dart';

/// How many gifts and rewards wait for the person, for the red number on the «Подарки» button of the
/// bottom bar. Null until the first answer.
final ValueNotifier<int> giftsWaiting = ValueNotifier(0);

/// The «Подарки» tab (variant Б of the mockup): the four chests at the top, the chosen one large with
/// «Открыть ×1 / ×5 / ×10», and below it what waits to be taken (gifts, a reward for the day's goal,
/// the chest of the day). Everything that belongs to the person and has not been opened yet is here;
/// the Главная no longer carries it.
class GiftsScreen extends StatefulWidget {
  const GiftsScreen({super.key});

  @override
  State<GiftsScreen> createState() => _GiftsScreenState();
}

class _GiftsScreenState extends State<GiftsScreen> {
  ChestBank? _bank = ApiClient.instance.cachedChests();
  List<AppNotification> _waiting = const [];
  String? _selected;
  final Map<String, int> _mode = {};
  bool _busy = false;
  String? _notice;
  Timer? _noticeTimer;

  @override
  void initState() {
    super.initState();
    dailyGoalTick.addListener(_load);
    ChestQueue.correction.addListener(_onCorrection);
    _load();
  }

  @override
  void dispose() {
    dailyGoalTick.removeListener(_load);
    ChestQueue.correction.removeListener(_onCorrection);
    _noticeTimer?.cancel();
    super.dispose();
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

  /// What the server has right now: the chests, and the gifts waiting in the inbox.
  Future<void> _load() async {
    await ChestQueue.flush();
    final bank = await ApiClient.instance.fetchChests();
    List<AppNotification> waiting = _waiting;
    try {
      waiting = [for (final n in (await ApiClient.instance.fetchNotifications()).items) if (n.action != null) n];
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _bank = bank ?? _bank;
      _waiting = waiting;
      _selected ??= _firstKind();
    });
    _announce();
  }

  void _announce() {
    final b = _bank;
    final daily = b != null && b.daily.enabled && !b.daily.claimed && b.daily.available ? 1 : 0;
    giftsWaiting.value = _waiting.length + daily;
  }

  String? _firstKind() {
    final b = _bank;
    if (b == null || b.types.isEmpty) return null;
    for (final t in b.types) {
      if (_count(t.key) > 0) return t.key;
    }
    return b.types.first.key;
  }

  int _count(String key) => _bank?.chests.where((c) => c.chestKey == key).length ?? 0;

  /// The multiplier actually in force: the chosen one, lowered while there are too few chests.
  int _multiplier(String key) {
    final n = _count(key);
    final chosen = _mode[key] ?? 1;
    if (chosen >= 10 && n >= 10) return 10;
    if (chosen >= 5 && n >= 5) return 5;
    return 1;
  }

  Future<void> _open(String key) async {
    final bank = _bank;
    if (_busy || bank == null) return;
    final m = _multiplier(key);
    _busy = true;
    ChestBank? result;
    try {
      result = await Navigator.of(context).push<ChestBank>(
        MaterialPageRoute(builder: (_) => ChestOpenScreen(bank: bank, chests: [for (final c in bank.chests) if (c.chestKey == key) c].take(m).toList())),
      );
    } finally {
      _busy = false; // live again the moment the opening screen is closed
    }
    if (result != null && mounted) setState(() => _bank = result);
    unawaited(_load());
  }

  Future<void> _claimDaily() async {
    try {
      final bank = await ApiClient.instance.claimDailyChest();
      if (mounted) setState(() => _bank = bank);
    } on ApiException catch (e) {
      if (mounted) _say(e.message);
      await _load(); // e.g. «already taken»: show what the server has
    } catch (_) {
      if (mounted) _say(tr('Не удалось. Проверьте интернет.'));
    }
    _announce();
  }

  /// «Забрать» on a gift or on the reward of the day's goal.
  Future<void> _take(AppNotification item) async {
    final id = int.tryParse((item.action ?? '').split(':').last);
    if (id == null) return;
    final isGift = (item.action ?? '').startsWith('claim_gift:');
    try {
      if (isGift) {
        await ApiClient.instance.claimGift(id);
      } else {
        await ApiClient.instance.claimDailyGoal(id);
      }
      if (!mounted) return;
      unawaited(ApiClient.instance.fetchEconomy());
      await showRewardClaimEffect(context, title: isGift ? tr('Подарок получен!') : tr('Цель дня выполнена!'), rewards: item.payload);
      dailyGoalTick.value++;
    } on ApiException catch (_) {
      // Taken somewhere else already: the list below simply loses the card.
    } catch (_) {
      return;
    }
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final bank = _bank;
    final key = _selected;
    final daily = bank?.daily;
    final dailyWaiting = daily != null && daily.enabled && !daily.claimed && daily.available;
    final total = bank?.chests.length ?? 0;
    final waitingCount = _waiting.length + (dailyWaiting ? 1 : 0);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: const ValueKey('gifts-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          Text(tr('Подарки'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: AppColors.primaryDark)),
          const SizedBox(height: 12),
          if (_notice != null)
            Container(
              key: const ValueKey('gifts-notice'),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: AppColors.violetSurface, borderRadius: BorderRadius.circular(12)),
              child: Text(_notice!, style: TextStyle(color: AppColors.primaryDark, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          if (bank != null && bank.types.isNotEmpty) ...[
            Row(children: [
              for (var i = 0; i < bank.types.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _kindTile(bank.types[i], bank.types[i].key == key)),
              ],
            ]),
            const SizedBox(height: 10),
            if (key != null) _hero(bank, key),
          ] else if (bank == null)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
          if (bank != null && total == 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(tr('Пока сундуков нет'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.secondaryText)),
            ),
          if (waitingCount > 0) ...[
            const SizedBox(height: 18),
            Row(children: [
              Text(tr('Ждут вас'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(99)),
                child: Text('$waitingCount', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
              ),
            ]),
            const SizedBox(height: 8),
            if (dailyWaiting) _dailyCard(daily),
            for (final n in _waiting) _giftCard(n),
          ] else if (bank != null)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Text(tr('Подарки и награды, которые ждут, будут здесь'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.secondaryText, fontSize: 13)),
            ),
        ],
      ),
    );
  }

  Widget _kindTile(ChestType t, bool on) {
    final n = _count(t.key);
    return GestureDetector(
      key: ValueKey('gift-kind-${t.key}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _selected = t.key),
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
        decoration: BoxDecoration(
          color: on ? AppColors.violetSurface : AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: on ? AppColors.primary : AppColors.cardBorder, width: on ? 2 : 1),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            Opacity(opacity: n == 0 ? 0.4 : 1, child: ChestImage(t.key, size: 52)),
            Positioned(
              top: -4,
              right: -2,
              child: Container(
                constraints: const BoxConstraints(minWidth: 20),
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(99)),
                child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
        ]),
      ),
    );
  }

  Widget _hero(ChestBank bank, String key) {
    final type = bank.types.firstWhere((t) => t.key == key, orElse: () => bank.types.first);
    final n = _count(key);
    final m = _multiplier(key);
    final options = [1, 5, 10].where((x) => x == 1 || n >= x).toList();
    return Container(
      key: ValueKey('gift-hero-$key'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: AppColors.cardBorder)),
      child: Column(children: [
        Opacity(opacity: n == 0 ? 0.45 : 1, child: ChestImage(key, size: 130)),
        const SizedBox(height: 6),
        Text(type.name, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
        const SizedBox(height: 2),
        Text(n == 0 ? tr('Пока таких сундуков нет') : tr('В запасе: {0}', [n]), style: TextStyle(fontSize: 13, color: AppColors.secondaryText)),
        if (n > 0) ...[
          const SizedBox(height: 12),
          if (options.length > 1)
            Row(children: [
              for (var i = 0; i < options.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    key: ValueKey('gift-mode-$key-${options[i]}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _mode[key] = options[i]),
                    child: Container(
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: m == options[i] ? AppColors.primary : AppColors.violetSurface, borderRadius: BorderRadius.circular(12)),
                      child: Text('×${options[i]}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: m == options[i] ? Colors.white : AppColors.primaryDark)),
                    ),
                  ),
                ),
              ],
            ]),
          if (options.length > 1) const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FlatGreenButton(
              key: ValueKey('gift-open-$key'),
              label: m > 1 ? '${tr('Открыть')} ×$m' : tr('Открыть'),
              onTap: _busy ? null : () => _open(key),
              compact: false,
            ),
          ),
        ],
      ]),
    );
  }

  Widget _card({required Widget leading, required String title, String? sub, List<RewardSpec> rewards = const [], Widget? action, Key? key}) => Container(
        key: key,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.cardBorder)),
        child: Row(children: [
          SizedBox(width: 46, height: 46, child: Center(child: leading)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
              if (sub != null && sub.isNotEmpty) Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.secondaryText)),
              if (rewards.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: RewardChips(rewards: rewards, size: 18, soft: true)),
            ]),
          ),
          if (action != null) ...[const SizedBox(width: 8), action],
        ]),
      );

  Widget _dailyCard(DailyChest daily) => _card(
        key: const ValueKey('gift-daily'),
        leading: ChestImage(daily.chestKey, size: 40),
        title: tr('Сундук дня'),
        sub: daily.conditions,
        action: FlatGreenButton(label: tr('Забрать'), onTap: _claimDaily, width: 110),
      );

  Widget _giftCard(AppNotification n) {
    final isGift = (n.action ?? '').startsWith('claim_gift:');
    return _card(
      key: ValueKey('gift-${n.id}'),
      leading: const GiftBadge(size: 40),
      title: n.title ?? (isGift ? tr('Подарок') : tr('Цель дня выполнена!')),
      sub: n.body,
      rewards: n.payload,
      action: FlatGreenButton(label: tr('Забрать'), onTap: () => _take(n), width: 110),
    );
  }
}
