import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../widgets/game_icons.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/season_summary.dart';
import '../theme/app_colors.dart';
import '../widgets/season_pass_ui.dart';

String summarySeasonName(SeasonSummary s) {
  final lang = appLanguage.value;
  if (lang == 'tg' && (s.seasonNameTg ?? '').isNotEmpty) return s.seasonNameTg!;
  if (lang == 'uz' && (s.seasonNameUz ?? '').isNotEmpty) return s.seasonNameUz!;
  return s.seasonName;
}

String _titleText(SeasonTitle t) {
  final lang = appLanguage.value;
  if (lang == 'tg' && (t.textTg ?? '').isNotEmpty) return t.textTg!;
  if (lang == 'uz' && (t.textUz ?? '').isNotEmpty) return t.textUz!;
  return t.text;
}

/// What goes into the share sheet.
String summaryShareText(SeasonSummary s) => tr(
  'Мой сезон «{0}» в GuYo: уровень {1}, {2} энергии, выучено слов: {3}, дней занятий: {4}.',
  [summarySeasonName(s), s.level, s.xp, s.wordsLearned, s.activeDays],
);

/// "Итоги сезона": the recap of the last finished season.
class SeasonSummaryScreen extends StatefulWidget {
  /// Shown at once with no request (used by tests and previews).
  final SeasonSummary? initial;
  const SeasonSummaryScreen({super.key, this.initial});

  @override
  State<SeasonSummaryScreen> createState() => _SeasonSummaryScreenState();
}

/// The summary card as a PNG (what gets shared). Null if it cannot be drawn.
Future<Uint8List?> captureCard(GlobalKey key, {double pixelRatio = 3}) async {
  try {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

class _SeasonSummaryScreenState extends State<SeasonSummaryScreen> {
  SeasonSummary? _summary;
  bool _loading = true;
  final GlobalKey _cardKey = GlobalKey();

  /// Shares the card as a picture (with the text under it); text alone if the picture fails.
  Future<void> _share(SeasonSummary s) async {
    final text = summaryShareText(s);
    final bytes = await captureCard(_cardKey);
    if (bytes == null) {
      await SharePlus.instance.share(ShareParams(text: text));
      return;
    }
    try {
      final file = File(
        '${Directory.systemTemp.path}/guyo_season_${s.seasonId}.png',
      );
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          files: [XFile(file.path, mimeType: 'image/png')],
        ),
      );
    } catch (_) {
      await SharePlus.instance.share(ShareParams(text: text));
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _summary = widget.initial;
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final s = await ApiClient.instance.fetchSeasonSummary();
    if (!mounted) return;
    setState(() {
      _summary = s;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(tr('Итоги сезона')),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : s == null
          ? Center(
              child: Text(
                tr('Пока нет завершённых сезонов'),
                style: TextStyle(color: AppColors.secondaryText),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                RepaintBoundary(
                  key: _cardKey,
                  child: Container(
                    color: AppColors.canvas,
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Column(
                      children: [
                        _SummaryHero(summary: s),
                        const SizedBox(height: 14),
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1.9,
                          children: [
                            _Stat(
                              icon: Icons.menu_book_rounded,
                              value: '${s.wordsLearned}',
                              label: tr('слов выучено'),
                            ),
                            _Stat(
                              icon: Icons.calendar_month_rounded,
                              value: '${s.activeDays}',
                              label: tr('дней занятий'),
                            ),
                            _Stat(
                              icon: Icons.card_giftcard_rounded,
                              value: '${s.rewardsClaimed}',
                              label: tr('наград получено'),
                            ),
                            _Stat(
                              icon: Icons.emoji_events_rounded,
                              value: s.rankName ?? '—',
                              label: s.seasonPoints == null
                                  ? tr('ранг')
                                  : tr('ранг, {0} звёзд', [s.seasonPoints!]),
                            ),
                          ],
                        ),
                        if (s.badges.isNotEmpty || s.titles.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              tr('Получено в сезоне'),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primaryDark,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 12,
                            runSpacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              for (final b in s.badges)
                                BadgeGlyph(badgeKey: b, size: 44),
                              for (final t in s.titles)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.violetSurface,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    _titleText(t),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    key: const ValueKey('summary-share'),
                    onPressed: () => _share(s),
                    icon: const Icon(Icons.ios_share_rounded),
                    label: Text(
                      tr('Поделиться'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _SummaryHero extends StatelessWidget {
  final SeasonSummary summary;
  const _SummaryHero({required this.summary});

  @override
  Widget build(BuildContext context) {
    final value = summary.maxLevel == 0
        ? 1.0
        : (summary.level / summary.maxLevel).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: passHeroGradient(AppColors.dark),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5862DD).withValues(alpha: 0.35),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          LevelRing(size: 116, progress: value, level: summary.level),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summarySeasonName(summary),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 2),
                IconText(
                  '⚡ ${summary.xp} ${tr('энергии')}',
                  style: const TextStyle(
                    fontSize: 32,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tr('уровень {0} из {1}', [summary.level, summary.maxLevel]),
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _Stat({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 26),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primaryDark,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
