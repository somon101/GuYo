import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/quest.dart';
import '../theme/app_colors.dart';

/// "Очки сегодня": what today's points are made of -- each grant with
/// what it was for, when, and how much. Only today is kept; it starts
/// empty again tomorrow.
Future<void> showPointsToday(BuildContext context, {required int total}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    isScrollControlled: true,
    builder: (_) => _PointsTodaySheet(total: total),
  );
}

class _PointsTodaySheet extends StatefulWidget {
  final int total;
  const _PointsTodaySheet({required this.total});

  @override
  State<_PointsTodaySheet> createState() => _PointsTodaySheetState();
}

class _PointsTodaySheetState extends State<_PointsTodaySheet> {
  late final Future<List<PointsTodayItem>> _items = ApiClient.instance.fetchPointsToday();

  String _time(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header: the total, big, with what it is.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 8, 6),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.gold.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.star_rounded, color: AppColors.gold, size: 26),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '+${widget.total}',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                          ),
                          Text(tr('очков сегодня'), style: TextStyle(fontSize: 13, color: AppColors.secondaryText)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: tr('Закрыть'),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, color: AppColors.secondaryText),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 0.6, color: Color(0xFFE6E8F2)),
              Flexible(
                child: FutureBuilder<List<PointsTodayItem>>(
                  future: _items,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
                      );
                    }
                    final items = snap.data;
                    if (items == null) return _note(Icons.wifi_off_rounded, tr('Не удалось загрузить данные'));
                    if (items.isEmpty) {
                      return _note(Icons.auto_awesome_rounded, tr('Сегодня очков пока нет. Выучите слово или пройдите квест!'));
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 0.6, thickness: 0.6, indent: 68, color: Color(0xFFEFF1F7)),
                      itemBuilder: (_, i) => _row(items[i]),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                child: Text(
                  tr('История хранится только за сегодня'),
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(PointsTodayItem item) {
    final isQuest = item.kind == 'quest';
    final color = isQuest ? AppColors.success : AppColors.primary;
    final title = isQuest ? (item.title ?? tr('Квест')) : tr('Новое слово');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(isQuest ? Icons.flag_rounded : Icons.menu_book_rounded, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
                ),
                const SizedBox(height: 1),
                Text(
                  [if (item.word != null) item.word!, _time(item.at)].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: AppColors.secondaryText),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '+${item.points}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFFB7791F)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _note(IconData icon, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.muted, size: 30),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: AppColors.secondaryText)),
          ],
        ),
      );
}
