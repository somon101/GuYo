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

  /// One section of the shop: a title, the products' own description and their packs in a row.
  List<Widget> _section(Map<String, dynamic> data, String type, String title) {
    final all = (data['products'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    final items = [for (final p in all) if ((p['item_type'] as String? ?? 'streak_freeze') == type) p];
    if (items.isEmpty) return const [];
    final balance = data['diamonds'] as int? ?? 0;
    final description = items.first['description'] as String? ?? '';
    return [
      Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppColors.primaryDark)),
      ),
      if (description.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
          child: Text(description, style: TextStyle(fontSize: 12.5, color: AppColors.secondaryText)),
        ),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - 16) / 3;
        return Wrap(spacing: 8, runSpacing: 14, children: [
          for (final p in items)
            SizedBox(
              width: w,
              child: ShopPack(
                key: ValueKey('shop-product-${p['id']}'),
                itemType: type,
                quantity: p['quantity'] as int? ?? 1,
                price: p['price_diamonds'] as int? ?? 0,
                affordable: balance >= (p['price_diamonds'] as int? ?? 0),
                tag: (p['quantity'] as int? ?? 1) >= 10 ? tr('Выгодно') : null,
                onTap: () => _confirm(p, balance),
              ),
            ),
        ]);
      }),
      const SizedBox(height: 18),
    ];
  }

  /// «Купить …?»: what is spent and what is left; the buy button is off when diamonds are short.
  Future<void> _confirm(Map<String, dynamic> product, int balance) async {
    final price = product['price_diamonds'] as int? ?? 0;
    final enough = balance >= price;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(28)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(tr('Купить «{0}»?', [product['name']]), textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
            const SizedBox(height: 6),
            Text(
              enough ? tr('Спишется {0} бриллиантов, останется {1}', [price, balance - price]) : tr('Не хватает бриллиантов'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.secondaryText),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              key: const ValueKey('shop-confirm'),
              onTap: enough ? () => Navigator.of(ctx).pop(true) : null,
              child: Opacity(
                opacity: enough ? 1 : 0.45,
                child: Container(
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(99)),
                  child: Text(tr('Купить за {0}', [price]), style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(tr('Отмена'))),
          ]),
        ),
      ),
    );
    if (ok == true) await _buy(product);
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
                  ..._section(data, 'streak_freeze', tr('Заморозки серии')),
                  ..._section(data, 'streak_merge', tr('Объединители')),
                  const _MoreDiamondsCell(),
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

/// The last card: where diamonds come from.
class _MoreDiamondsCell extends StatelessWidget {
  const _MoreDiamondsCell();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), color: AppColors.surface),
        child: Row(children: [
          const GiftArt(size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Нужно больше?'), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
              const SizedBox(height: 2),
              Text(tr('Бриллианты дают подарки за уровни пропуска сезона'), style: TextStyle(fontSize: 12, color: AppColors.secondaryText)),
            ]),
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
