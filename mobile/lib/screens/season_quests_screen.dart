import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/dictionary.dart';
import '../models/quest.dart';
import '../theme/app_colors.dart';
import '../widgets/quest_ui.dart';
import 'home_dashboard_screen.dart';
import 'quest_attempt_screen.dart';

const Map<String, String> _exerciseLabels = {
  'true_or_false': 'Правда или ложь',
  'matching': 'Сопоставление',
  'build_word': 'Собери слово',
  'speaking_word': 'Произнеси слово',
  'listen_word': 'Услышь слово',
};

const Map<String, IconData> _exerciseIcons = {
  'true_or_false': Icons.rule_rounded,
  'matching': Icons.compare_arrows_rounded,
  'build_word': Icons.abc_rounded,
  'speaking_word': Icons.mic_rounded,
  'listen_word': Icons.headphones_rounded,
};

/// "Квесты сезона": the season banner, the user's standing in it, the
/// permanent "Квест дня", and every daily quest that currently exists.
///
/// The quest list is entirely backend-driven -- however many quests an
/// admin has enabled is however many rows appear here, with their own
/// targets and rewards. Nothing about the set is hardcoded.
class SeasonQuestsScreen extends StatefulWidget {
  final GuyoDictionary dictionary;
  final VoidCallback onOpenLessons;

  const SeasonQuestsScreen({super.key, required this.dictionary, required this.onOpenLessons});

  @override
  State<SeasonQuestsScreen> createState() => _SeasonQuestsScreenState();
}

class _SeasonQuestsScreenState extends State<SeasonQuestsScreen> {
  bool _isLoading = true;
  String? _loadError;
  SeasonQuestOverview? _overview;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final overview = await ApiClient.instance.fetchSeasonQuestOverview(widget.dictionary.id);
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Не удалось загрузить квесты';
      });
    }
  }

  Future<void> _openQuest(AvailableQuest quest) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuestAttemptScreen(
          dictionary: widget.dictionary,
          questId: quest.id,
          questName: quest.name,
        ),
      ),
    );
    _load();
  }

  void _openLessons() {
    // The daily-words quest is carried out in "Уроки", which is a tab of
    // the app shell below this route -- so pop back to it and switch.
    Navigator.of(context).pop();
    widget.onOpenLessons();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Квесты',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
        ),
        iconTheme: const IconThemeData(color: AppColors.primaryDark),
      ),
      body: SafeArea(
        child: RefreshIndicator(onRefresh: _load, child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return ListView(children: const [SizedBox(height: 220, child: Center(child: CircularProgressIndicator()))]);
    }
    if (_loadError != null) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: const Text('Повторить')),
              ],
            ),
          ),
        ],
      );
    }

    final overview = _overview!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        _SeasonBanner(overview: overview),
        const SizedBox(height: 14),
        _StatsRow(overview: overview),
        const SizedBox(height: 14),
        DailyQuestCard(
          pointsPerLearnedWord: overview.pointsPerLearnedWord,
          wordsLearnedToday: overview.wordsLearnedToday,
          onTap: _openLessons,
        ),
        const SizedBox(height: 22),
        SectionHeader(
          title: 'Ежедневные квесты',
          trailing: '${overview.questsDoneToday} / ${overview.questsTotal}',
        ),
        const SizedBox(height: 12),
        if (overview.quests.isEmpty)
          const GuyoCard(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Ежедневных квестов пока нет',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.secondaryText),
              ),
            ),
          )
        else
          for (final quest in overview.quests) ...[
            _QuestRow(quest: quest, onTap: () => _openQuest(quest)),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

/// The big season banner.
///
/// Three clearly separate layers rather than one soft pile: the gradient
/// is atmosphere, the artwork sits on its own white plate, and the
/// season's dates and remaining time live in their own panel. The quest
/// counter deliberately does NOT appear here -- it is a different measure
/// from "how much of the season is left", and the two sharing a bar was
/// exactly what made this block hard to read.
class _SeasonBanner extends StatelessWidget {
  final SeasonQuestOverview overview;
  const _SeasonBanner({required this.overview});

  @override
  Widget build(BuildContext context) {
    final season = overview.season;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppColors.bannerGradient,
        ),
        borderRadius: BorderRadius.circular(AppShapes.bannerRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SeasonIconPlate(iconUrl: season?.iconUrl, iconSize: 78),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (season != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppShapes.pillRadius),
                        ),
                        child: Text(
                          season.name,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const SizedBox(height: 8),
                    const Text(
                      'Квесты сезона',
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Выполняй задания, получай очки и повышай свой ранг.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.secondaryText, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (season == null)
            const Text(
              'Сейчас нет активного сезона',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.secondaryText),
            )
          else
            SeasonTimeline(
              startsAt: season.startsAt,
              endsAt: season.endsAt,
              daysLeft: overview.daysLeft,
              daysTotal: overview.daysTotal,
            ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final SeasonQuestOverview overview;
  const _StatsRow({required this.overview});

  @override
  Widget build(BuildContext context) {
    return GuyoCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: StatColumn(
                icon: Icons.star_rounded,
                value: '+${overview.pointsToday}',
                label: 'Очков сегодня',
                iconColor: AppColors.rewardText,
              ),
            ),
            const StatDivider(),
            Expanded(
              child: StatColumn(
                icon: Icons.emoji_events_rounded,
                value: overview.rankPosition == null ? '—' : '#${overview.rankPosition}',
                label: 'Место в рейтинге',
              ),
            ),
            const StatDivider(),
            Expanded(
              child: StatColumn(
                icon: Icons.track_changes_rounded,
                value: '${overview.questsDoneToday} / ${overview.questsTotal}',
                label: 'Квестов выполнено',
                iconColor: AppColors.success,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One daily quest: what it targets, how far along today, what it pays.
///
/// Tappable only while the backend says it's attemptable -- a quest with
/// no eligible word left today says so instead of opening a round that
/// would immediately fail.
class _QuestRow extends StatelessWidget {
  final AvailableQuest quest;
  final VoidCallback onTap;

  const _QuestRow({required this.quest, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final done = quest.isDoneToday;
    final canAttempt = quest.available && !done;
    final subtitle = done
        ? 'Выполнено сегодня'
        : quest.available
            ? '${_exerciseLabels[quest.exerciseKey] ?? quest.exerciseKey} · ${quest.wordLevelName}'
            : 'Нет подходящих слов';

    return GuyoCard(
      radius: AppShapes.rowRadius,
      padding: const EdgeInsets.all(12),
      onTap: canAttempt ? onTap : null,
      child: Row(
        children: [
          RoundIconChip(
            icon: _exerciseIcons[quest.exerciseKey] ?? Icons.flag_rounded,
            background: done ? AppColors.successLight : AppColors.violetSurface,
            iconColor: done
                ? AppColors.success
                : quest.available
                    ? AppColors.primary
                    : AppColors.muted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  quest.name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.secondaryText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 7),
                QuestProgressBar(
                  value: quest.completedToday,
                  target: quest.dailyTarget,
                  height: 6,
                  color: done ? AppColors.success : AppColors.primary,
                  label: '${quest.completedToday} / ${quest.dailyTarget}',
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RewardBadge(points: quest.rewardPoints),
              const SizedBox(height: 6),
              if (done)
                const Icon(Icons.check_circle_rounded, size: 20, color: AppColors.success)
              else if (canAttempt)
                const Icon(Icons.chevron_right, size: 20, color: AppColors.muted)
              else
                const SizedBox(height: 20),
            ],
          ),
        ],
      ),
    );
  }
}
