import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../widgets/season_pass_ui.dart' show RewardStyle, showRewardDialog;

const _gold = Color(0xFFFFC857);
const _ink = Color(0xFF171A2B);

Future<void> openEconomy(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const EconomyScreen()));

Future<void> openStreakHistory(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const StreakHistoryScreen()));

class EconomyScreen extends StatefulWidget {
  const EconomyScreen({super.key});
  @override
  State<EconomyScreen> createState() => _EconomyScreenState();
}

class _EconomyScreenState extends State<EconomyScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final AudioPlayer _rewardPlayer = AudioPlayer();
  Map<String, dynamic>? _data;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _rewardPlayer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.instance.fetchEconomy();
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _buy(Map<String, dynamic> product) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      _data = await ApiClient.instance.buyShopProduct(product['id'] as int);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openGift(Map<String, dynamic> gift) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await ApiClient.instance.openGift(gift['id'] as int);
      _data = await ApiClient.instance.fetchEconomy();
      if (!mounted) return;
      setState(() {});
      await _rewardPlayer.play(AssetSource('sounds/correct-answer.mp3'));
      if (!mounted) return;
      final isFreeze = result['kind'] == 'freeze';
      await showRewardDialog(
        context,
        style: isFreeze
            ? const RewardStyle(
                [Color(0xFF7FDBFF), Color(0xFF3A7BFF)],
                Icons.ac_unit_rounded,
                '',
              )
            : const RewardStyle(
                [Color(0xFF92F2FF), Color(0xFF6558FF)],
                Icons.diamond_rounded,
                '',
              ),
        title: tr('Поздравляем!'),
        text: isFreeze
            ? tr('Заморозка серии +1')
            : '+${result['amount']} ${tr('бриллиантов')}',
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${tr('Серия объединена')}: ${result['current_streak_days']}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F5FB),
      appBar: AppBar(
        title: Text(tr('Магазин и подарки')),
        actions: [
          if (data != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '💎 ${data['diamonds']}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF5044C8),
                  ),
                ),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: tr('Магазин')),
            Tab(text: tr('Подарки')),
          ],
        ),
      ),
      body: data == null
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _inventory(data),
                      for (final p
                          in (data['products'] as List<dynamic>)
                              .cast<Map<String, dynamic>>())
                        _productCard(p, () => _buy(p)),
                      if ((data['streak_merge_items'] as int? ?? 0) > 0)
                        FilledButton.icon(
                          onPressed: _busy ? null : _merge,
                          icon: const Icon(Icons.auto_awesome),
                          label: Text(tr('Объединить историю серии')),
                        ),
                    ],
                  ),
                ),
                RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final g
                          in (data['gifts'] as List<dynamic>)
                              .cast<Map<String, dynamic>>())
                        _giftCard(g),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _inventory(Map<String, dynamic> data) => Card(
    color: _ink,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          const Icon(Icons.ac_unit_rounded, color: Colors.lightBlueAccent),
          const SizedBox(width: 7),
          Text(
            '${data['streak_freezes']}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 20),
            const _MergeSymbol(),
          const SizedBox(width: 7),
          Text(
            '${data['streak_merge_items']}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          const Icon(Icons.diamond_rounded, color: Color(0xFF87EFFF)),
          const SizedBox(width: 6),
          Text(
            '${data['diamonds']}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _productCard(Map<String, dynamic> p, VoidCallback buy) {
    final merge = p['item_type'] == 'streak_merge';
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: ListTile(
      leading: merge ? const _MergeSymbol() : const Icon(Icons.ac_unit_rounded, color: Colors.lightBlue),
        title: Text(p['name'] as String),
        subtitle: Text(p['description'] as String? ?? ''),
        trailing: FilledButton(
          onPressed: _busy ? null : buy,
          child: Text('💎 ${p['price_diamonds']}'),
        ),
      ),
    );
  }

  Widget _giftCard(Map<String, dynamic> g) {
    final opened = g['opened'] as Map<String, dynamic>?;
    final enabled = g['available'] == true && !_busy;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(
          Icons.card_giftcard_rounded,
          color: Colors.deepPurple,
          size: 32,
        ),
        title: Text(g['name'] as String),
        subtitle: Text(
          opened == null
              ? (g['description'] as String? ?? '')
              : '${tr('Получено')}: ${opened['amount']} ${opened['kind'] == 'freeze'
                    ? tr('заморозок')
                    : opened['kind'] == 'xp'
                    ? '⚡'
                    : tr('бриллиантов')}',
        ),
        trailing: FilledButton(
          onPressed: enabled ? () => _openGift(g) : null,
          child: Text(opened != null ? tr('Открыт') : tr('Открыть')),
        ),
      ),
    );
  }
}

/// Two flame halves joined by a bright spark, the symbol for merging streaks.
class _MergeSymbol extends StatelessWidget {
  const _MergeSymbol();
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 36,
        height: 32,
        child: Stack(alignment: Alignment.center, children: [
          const Positioned(left: 0, child: Icon(Icons.local_fire_department_rounded, size: 22, color: Color(0xFFFF7138))),
          const Positioned(right: 0, child: Icon(Icons.local_fire_department_rounded, size: 22, color: Color(0xFFE94C77))),
          Container(width: 18, height: 18, decoration: const BoxDecoration(color: Color(0xFFFFCF5B), shape: BoxShape.circle), child: const Icon(Icons.bolt_rounded, size: 14, color: Color(0xFF743C20))),
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
            .showSnackBar(SnackBar(content: Text(e.toString())));
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
    final days = (_data?['days'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final firstOffset = DateTime(_month.year, _month.month, 1).weekday - 1;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F5FB),
      appBar: AppBar(title: Text(tr('История серии'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () => _shift(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(
                  '${_month.month.toString().padLeft(2, '0')}.${_month.year}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                IconButton(
                  onPressed: () => _shift(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          if (_data != null)
            Text(
              '${tr('Серия')}: ${_data!['current_streak_days']}   •   ${tr('Занятий')}: ${_data!['active_days']}   •   ${tr('Пропусков')}: ${_data!['missed_days']}',
            ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: GridView.builder(
              shrinkWrap: true,
              itemCount: firstOffset + days.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 5,
                crossAxisSpacing: 5,
              ),
              itemBuilder: (_, i) {
                if (i < firstOffset) return const SizedBox.shrink();
                final d = days[i - firstOffset];
                final state = d['state'];
                final Color color = switch (state) {
                  'active' => const Color(0xFFFF8A3D),
                  'frozen' => Colors.lightBlue,
                  'missed' => Colors.redAccent.withValues(alpha: .3),
                  _ => Colors.white,
                };
                return InkWell(
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
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${i - firstOffset + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color:
                            state == 'missed' ||
                                state == 'active' ||
                                state == 'frozen'
                            ? Colors.white
                            : Colors.black87,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${tr('Объединённых дней')}: ${_data?['merged_days'] ?? 0}',
            style: const TextStyle(
              color: Colors.deepPurple,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          if (_data == null) const CircularProgressIndicator(),
        ],
      ),
    );
  }
}
