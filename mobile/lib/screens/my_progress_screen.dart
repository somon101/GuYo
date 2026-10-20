import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/my_progress.dart';
import '../theme/app_colors.dart';

/// «Мой путь»: how many words were learned each week, drawn as bars.
class MyProgressScreen extends StatefulWidget {
  /// Shown at once with no request (used by tests and previews).
  final MyProgress? initial;
  const MyProgressScreen({super.key, this.initial});

  @override
  State<MyProgressScreen> createState() => _MyProgressScreenState();
}

class _MyProgressScreenState extends State<MyProgressScreen> {
  MyProgress? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _data = widget.initial;
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final data = await ApiClient.instance.fetchMyProgress();
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(tr('Мой путь')), backgroundColor: Colors.transparent, scrolledUnderElevation: 0),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : data == null
              ? Center(child: Text(tr('Не удалось. Проверьте интернет.'), style: TextStyle(color: AppColors.secondaryText)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                  children: [
                    Row(
                      children: [
                        Expanded(child: _Tile(value: '${data.totalWords}', label: tr('слов выучено'))),
                        const SizedBox(width: 10),
                        Expanded(child: _Tile(value: '${data.totalActiveDays}', label: tr('дней занятий'))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _Tile(value: '${data.thisWeek}', label: _compare(data)),
                    const SizedBox(height: 18),
                    Text(tr('Слов по неделям'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
                    const SizedBox(height: 10),
                    Container(
                      key: const ValueKey('progress-chart'),
                      height: 190,
                      padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: WeeklyBarsPainter(
                          values: [for (final w in data.weeks) w.words],
                          bar: AppColors.primary,
                          highlight: AppColors.success,
                          text: AppColors.secondaryText,
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  String _compare(MyProgress d) {
    final diff = d.thisWeek - d.lastWeek;
    if (diff > 0) return tr('слов на этой неделе, на {0} больше прошлой', [diff]);
    if (diff < 0) return tr('слов на этой неделе, на {0} меньше прошлой', [-diff]);
    return tr('слов на этой неделе, как и на прошлой');
  }
}

class _Tile extends StatelessWidget {
  final String value;
  final String label;
  const _Tile({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
        child: Row(
          children: [
            Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.primaryDark)),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: AppColors.secondaryText))),
          ],
        ),
      );
}

/// Bars for each week, the latest one highlighted; the value sits above each bar.
class WeeklyBarsPainter extends CustomPainter {
  final List<int> values;
  final Color bar;
  final Color highlight;
  final Color text;
  const WeeklyBarsPainter({required this.values, required this.bar, required this.highlight, required this.text});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final top = values.reduce((a, b) => a > b ? a : b);
    final maxValue = top == 0 ? 1 : top;
    const labelH = 16.0;
    final slot = size.width / values.length;
    final barW = slot * 0.58;
    final chartH = size.height - labelH;
    for (var i = 0; i < values.length; i++) {
      final h = chartH * values[i] / maxValue;
      final left = i * slot + (slot - barW) / 2;
      final rect = RRect.fromRectAndRadius(Rect.fromLTWH(left, chartH - h, barW, h), const Radius.circular(5));
      canvas.drawRRect(rect, Paint()..color = i == values.length - 1 ? highlight : bar.withValues(alpha: 0.75));
      if (values[i] > 0) {
        final tp = TextPainter(
          text: TextSpan(text: '${values[i]}', style: TextStyle(fontSize: 10, color: text, fontWeight: FontWeight.w700)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(left + (barW - tp.width) / 2, chartH - h - tp.height - 1));
      }
    }
    final base = Paint()
      ..color = text.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, chartH), Offset(size.width, chartH), base);
  }

  @override
  bool shouldRepaint(WeeklyBarsPainter old) => old.values != values || old.bar != bar;
}
