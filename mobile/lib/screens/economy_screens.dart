import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../widgets/gift_art.dart';
import '../widgets/shop_ui.dart';


Future<void> openEconomy(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const EconomyScreen()));

Future<void> openStreakHistory(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const StreakHistoryScreen()));

class EconomyScreen extends StatefulWidget {
  /// Shown at once with no request (used by tests and previews).
  final Map<String, dynamic>? initial;
  const EconomyScreen({super.key, this.initial});
  @override
  State<EconomyScreen> createState() => _EconomyScreenState();
}

/// «Магазин»: the diamond balance and what it buys. Diamonds themselves come
/// only from season-pass gifts, so there is no gifts tab any more.
class _EconomyScreenState extends State<EconomyScreen> {
  Map<String, dynamic>? _data;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _data = widget.initial ?? ApiClient.instance.cachedEconomy();
    if (widget.initial == null) _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.instance.fetchEconomy();
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _buy(Map<String, dynamic> product) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      _data = await ApiClient.instance.buyShopProduct(product['id'] as int);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('${tr('Куплено')}: ${product['name']}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _merge() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await ApiClient.instance.useStreakMerge();
      _data = await ApiClient.instance.fetchEconomy();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
          SnackBar(content: Text('${tr('Серия объединена')}: ${result['current_streak_days']}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(tr('Магазин'), style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark)),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: data == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                children: [
                  ShopHeader(
                    diamonds: data['diamonds'] as int? ?? 0,
                    freezes: data['streak_freezes'] as int? ?? 0,
                    merges: data['streak_merge_items'] as int? ?? 0,
                  ),
                  const SizedBox(height: 18),
                  GridView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    // A fixed height, not a ratio: long names and large
                    // system fonts must never overflow a card.
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      mainAxisExtent: 268,
                    ),
                    children: [
                      for (final p in (data['products'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>())
                        ShopCard(
                          key: ValueKey('shop-product-${p['id']}'),
                          name: p['name'] as String,
                          description: p['description'] as String? ?? '',
                          itemType: p['item_type'] as String? ?? 'streak_freeze',
                          quantity: p['quantity'] as int? ?? 1,
                          price: p['price_diamonds'] as int? ?? 0,
                          affordable: !_busy && (data['diamonds'] as int? ?? 0) >= (p['price_diamonds'] as int? ?? 0),
                          tag: (p['quantity'] as int? ?? 1) >= 10 ? tr('Выгодно') : null,
                          onBuy: () => _buy(p),
                        ),
                      const _MoreDiamondsCell(),
                    ],
                  ),
                  if ((data['streak_merge_items'] as int? ?? 0) > 0) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _busy ? null : _merge,
                      icon: const Icon(Icons.auto_awesome),
                      label: Text(tr('Объединить историю серии')),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

/// The last cell: where diamonds come from.
class _MoreDiamondsCell extends StatelessWidget {
  const _MoreDiamondsCell();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: AppColors.cardBorder, width: 2),
          color: AppColors.surface,
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const GiftArt(size: 64),
          const SizedBox(height: 6),
          Text(tr('Нужно больше?'), style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark)),
          const SizedBox(height: 4),
          Flexible(
            child: Text(
              tr('Бриллианты дают подарки за уровни пропуска сезона'),
              textAlign: TextAlign.center,
              overflow: TextOverflow.fade,
              style: TextStyle(fontSize: 11.5, color: AppColors.secondaryText),
            ),
          ),
        ]),
      );
}

class StreakHistoryScreen extends StatefulWidget {
  const StreakHistoryScreen({super.key});
  @override
  State<StreakHistoryScreen> createState() => _StreakHistoryScreenState();
}

class _StreakHistoryScreenState extends State<StreakHistoryScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, dynamic>? _data;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ApiClient.instance.fetchStreakHistory(_month);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _shift(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _data = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final days = (_data?['days'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    final firstOffset = DateTime(_month.year, _month.month, 1).weekday - 1;
    final dark = Theme.of(context).brightness == Brightness.dark;
    const fire = Color(0xFFFF8A3D);
    const ice = Color(0xFF4FB8EA);
    final missBg = dark ? const Color(0xFF4A2A2D) : const Color(0xFFF3C9CB);
    final missInk = dark ? const Color(0xFFFF8D93) : const Color(0xFFC23B43);
    final letters = [tr('Пн'), tr('Вт'), tr('Ср'), tr('Чт'), tr('Пт'), tr('Сб'), tr('Вс')];

    Widget stat(String value, String label) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
            child: Column(children: [
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: AppColors.primaryDark)),
              Text(label, style: TextStyle(fontSize: 12, color: AppColors.secondaryText)),
            ]),
          ),
        );
    Widget legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 5),
          Text(t, style: TextStyle(fontSize: 12, color: AppColors.secondaryText)),
        ]);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(tr('История серии')),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            IconButton(onPressed: () => _shift(-1), icon: Icon(Icons.chevron_left, color: AppColors.secondaryText)),
            Text('${_month.month.toString().padLeft(2, '0')}.${_month.year}',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.primaryDark)),
            IconButton(onPressed: () => _shift(1), icon: Icon(Icons.chevron_right, color: AppColors.secondaryText)),
          ]),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(24)),
            child: Column(children: [
              Row(children: [
                for (final l in letters)
                  Expanded(child: Center(child: Text(l, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.secondaryText)))),
              ]),
              const SizedBox(height: 6),
              if (_data == null)
                const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: firstOffset + days.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisSpacing: 5, crossAxisSpacing: 5),
                  itemBuilder: (_, i) {
                    if (i < firstOffset) return const SizedBox.shrink();
                    final d = days[i - firstOffset];
                    final state = d['state'];
                    final Color bg = switch (state) {
                      'active' => fire,
                      'frozen' => ice,
                      'missed' => missBg,
                      _ => AppColors.violetSurface,
                    };
                    final Color ink = switch (state) {
                      'active' || 'frozen' => Colors.white,
                      'missed' => missInk,
                      _ => AppColors.secondaryText,
                    };
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: Text('${d['date']}'),
                          content: Text(
                            '${tr('Выучено слов')}: ${d['words_learned']}\n${tr('Завершено уроков')}: ${d['lessons_completed']}\n${tr('День')}: ${tr(state == 'active'
                                ? 'Занимался'
                                : state == 'frozen'
                                    ? 'Заморожен'
                                    : state == 'missed'
                                        ? 'Пропущен'
                                        : state == 'future'
                                            ? 'Будущий'
                                            : 'Сегодня')}',
                          ),
                        ),
                      ),
                      child: Container(
                        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
                        alignment: Alignment.center,
                        child: Text('${i - firstOffset + 1}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: ink)),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 12),
              Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 6, children: [
                legend(fire, tr('Занимался')),
                legend(ice, tr('Заморожен')),
                legend(missInk.withValues(alpha: 0.6), tr('Пропущен')),
              ]),
            ]),
          ),
          if (_data != null) ...[
            const SizedBox(height: 10),
            Row(children: [
              stat('${_data!['current_streak_days']}', tr('Серия')),
              const SizedBox(width: 8),
              stat('${_data!['active_days']}', tr('Занятий')),
              const SizedBox(width: 8),
              stat('${_data!['missed_days']}', tr('Пропусков')),
            ]),
            if ((_data!['merged_days'] ?? 0) != 0) ...[
              const SizedBox(height: 10),
              Center(child: Text('${tr('Объединённых дней')}: ${_data!['merged_days']}', style: TextStyle(color: AppColors.secondaryText, fontWeight: FontWeight.w700))),
            ],
          ],
        ],
      ),
    );
  }
}
