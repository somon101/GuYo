import 'streak_sheet.dart';
import '../widgets/animated_fire.dart';
import '../services/streak_state.dart';
import '../l10n/l10n.dart';
import '../services/disk_cache.dart';
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../services/session_cache.dart';
import '../models/dictionary.dart';
import '../models/quest.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import 'points_today_sheet.dart';
import '../widgets/review_due_card.dart';
import '../theme/slogans.dart';
import '../theme/time_of_day.dart';
import '../widgets/quest_ui.dart';
import '../widgets/user_avatar.dart';
import '../widgets/user_name.dart';
import 'season_quests_screen.dart';
import '../widgets/daily_goal_card.dart';
import '../widgets/season_card.dart';
import '../widgets/home_tiles.dart';
import '../widgets/skeleton.dart';

/// The app's own slogan fetch, as a plain function so the default
/// [BackendSloganSource] can be a const value.
Future<String?> fetchTodaySloganFromApi() => ApiClient.instance.fetchTodaySlogan();

/// "Главная": the greeting, the lesson counter and the season block.
///
/// Replaces the old menu-of-links screen. Every number shown here is the
/// backend's own, fetched in one call (GET /quests/overview) that reads
/// the season, rating and quest systems that already exist -- this screen
/// owns no state and computes nothing.
class HomeDashboardScreen extends StatefulWidget {
  final GuyoDictionary dictionary;

  /// Switches the app to the "Уроки" tab -- where the "изучение новых
  /// слов" quest is actually carried out.
  final VoidCallback onOpenLessons;

  /// Switches the app to the "Профиль" tab. Профиль is a sibling tab
  /// rather than a route, so the greeting asks the shell to switch
  /// instead of pushing a second copy of that screen.
  final VoidCallback onOpenProfile;

  /// Switches the app to the "Рейтинг" tab -- "место в рейтинге" opens it.
  final VoidCallback? onOpenRating;

  /// Where the greeting's line comes from. Swappable by construction --
  /// the default asks the admin-curated set and falls back to the built-in
  /// list; a test hands in a fixed one (see SloganSource).
  final SloganSource sloganSource;

  const HomeDashboardScreen({
    super.key,
    required this.dictionary,
    required this.onOpenLessons,
    required this.onOpenProfile,
    this.onOpenRating,
    this.sloganSource = const BackendSloganSource(fetch: fetchTodaySloganFromApi),
  });

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  bool _isLoading = true;
  String? _loadError;
  SeasonQuestOverview? _overview;
  UserProfile? _profile;
  // The admin-curated line for today, or the built-in fallback -- resolved
  // by the source, never decided here.
  String? _slogan;
  final GlobalKey<ReviewDueCardState> _reviewKey = GlobalKey<ReviewDueCardState>();

  String get _cacheKey => 'home-${widget.dictionary.id}';

  @override
  void initState() {
    super.initState();
    var cached = SessionCache.get<(SeasonQuestOverview, UserProfile, String)>(_cacheKey);
    if (cached == null) {
      // Last launch's data, kept on the device.
      final overview = ApiClient.instance.cachedSeasonQuestOverview(widget.dictionary.id);
      final profile = ApiClient.instance.cachedMyProfile();
      if (overview != null && profile != null) {
        cached = (overview, profile, DiskCache.get('slogan') ?? '');
        SessionCache.put(_cacheKey, cached);
      }
    }
    if (cached != null) {
      _overview = cached.$1;
      _profile = cached.$2;
      _slogan = cached.$3;
      _isLoading = false;
    }
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      // Data already on screen stays there while it refreshes.
      _isLoading = _overview == null;
      _loadError = null;
    });
    _reviewKey.currentState?.reload();
    try {
      final results = await Future.wait([
        ApiClient.instance.fetchSeasonQuestOverview(widget.dictionary.id),
        ApiClient.instance.fetchMyProfile(),
        widget.sloganSource.today(),
      ]);
      if (!mounted) return;
      setState(() {
        _overview = results[0] as SeasonQuestOverview;
        _profile = results[1] as UserProfile;
        _slogan = results[2] as String;
        _isLoading = false;
      });
      SessionCache.put(_cacheKey, (_overview!, _profile!, _slogan!));
      DiskCache.put('slogan', _slogan!);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (_overview == null) _loadError = tr('Не удалось загрузить данные');
      });
    }
  }

  Future<void> _openSeasonQuests() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SeasonQuestsScreen(
          dictionary: widget.dictionary,
          onOpenLessons: widget.onOpenLessons,
        ),
      ),
    );
    // Coming back from a quest attempt changes points and progress.
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.canvas,
      child: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final overview = _overview;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        _Greeting(
          profile: _profile,
          slogan: _slogan,
          onOpenProfile: widget.onOpenProfile,
        ),
        // The main card: today's word goal with «Продолжить».
        DailyGoalCard(onContinue: widget.onOpenLessons),
        const SizedBox(height: 14),
        // The season (variant B): one card right after the goal.
        if (_isLoading)
          const Skeleton(
            child: Column(
              children: [
                SkeletonBox(height: 150, radius: AppShapes.cardRadius),
                SizedBox(height: 14),
                SkeletonBox(height: 110, radius: AppShapes.cardRadius),
                SizedBox(height: 14),
                SkeletonBox(height: 110, radius: AppShapes.cardRadius),
              ],
            ),
          )
        else if (_loadError != null)
          GuyoCard(
            child: Column(
              children: [
                Text(_loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: Text(tr('Повторить'))),
              ],
            ),
          )
        else if (overview != null)
          SeasonCard(
            overview: overview,
            onOpenHeader: _openSeasonQuests,
            onOpenPoints: () => showPointsToday(context, total: overview.pointsToday),
            onOpenRating: widget.onOpenRating,
            onOpenQuests: _openSeasonQuests,
            // The quest of the day opens the quests section itself.
            onQuestOfDay: _openSeasonQuests,
          ),
        const SizedBox(height: 18),
        _SectionTitle(tr('Мои награды')),
        const SizedBox(height: 10),
        const HomeTilesRow(),
        const SizedBox(height: 18),
        _SectionTitle(tr('Сегодня')),
        const SizedBox(height: 10),
        // Words being forgotten right now; hides itself when none are.
        ReviewDueCard(key: _reviewKey, dictionary: widget.dictionary),
      ],
    );
  }
}

/// Avatar + "Привет, {имя}" + the day's slogan. The avatar is the user's
/// real uploaded photo when they have one, and the app's existing
/// generated default when they don't -- the same UserAvatar the Profile
/// screen uses, never a second rendering of it.
class _Greeting extends StatelessWidget {
  final UserProfile? profile;

  /// Null only while the first load is still in flight -- the row keeps
  /// its height rather than appearing late and shifting everything below.
  final String? slogan;

  final VoidCallback onOpenProfile;

  const _Greeting({required this.profile, required this.slogan, required this.onOpenProfile});

  @override
  Widget build(BuildContext context) {
    final login = profile?.login ?? '';
    // Flat header (App Starter style): photo, name and slogan, the streak at the right.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
      children: [
        // The photo is the way into Профиль -- the same screen the bottom
        // bar reaches, never a second copy of it.
        Semantics(
          button: true,
          label: tr('Открыть профиль'),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpenProfile,
            child: UserAvatar(avatarUrl: profile?.avatarUrl, login: login, size: 48, frame: profile?.frame),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: UserNameText(
                      login.isEmpty ? tr('Привет!') : tr('Привет, {0}', [login]),
                      isPremium: profile?.isPremium ?? false,
                      badge: profile?.badge,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Sunrise, sun, sunset or moon, decided from THIS DEVICE's clock --
                  // see theme/time_of_day.dart.
                  const DayPartIcon(size: 22),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                slogan ?? '',
                style: TextStyle(fontSize: 13.5, color: AppColors.secondaryText),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (profile != null) ...[
          const SizedBox(width: 8),
          _StreakPill(profile: profile!),
        ],
      ],
      ),
    );
  }
}

/// The streak on Главная: the flame (grey until today is earned) and the
/// day count; tapping opens the streak sheet.
class _StreakPill extends StatelessWidget {
  final UserProfile profile;
  const _StreakPill({required this.profile});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool?>(
      valueListenable: streakLitToday,
      builder: (context, litNow, _) {
        final lit = litNow ?? profile.streakActiveToday;
        final days = streakDays.value ?? profile.currentStreakDays;
        return Semantics(
          button: true,
          label: lit ? tr('Серия: {0}', [days]) : tr('Сегодня ещё не занимались'),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showStreakSheet(context, streakDays: days),
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
              decoration: BoxDecoration(
                color: lit ? const Color(0xFFFFF0E6) : AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: lit ? const Color(0xFFFFD2B3) : AppColors.cardBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedFire(size: 28, lit: lit),
                  Text(
                    '$days',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: lit ? const Color(0xFFFF7A29) : AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The one big block on Главная: the season header with its own icon, the
/// three live stats, and the featured "Квест дня".
/// "Квест дня": the permanent "изучение новых слов" quest.
///
/// NOT a new mechanic -- it is the existing system quest, whose reward
/// already fires wherever a word is first learned (Уроки/Практика/Квесты
/// all share the one award path). It has no attempt flow of its own, so
/// tapping it goes to "Уроки", where new words are actually learned.
class DailyQuestCard extends StatelessWidget {
  final int pointsPerLearnedWord;
  final int wordsLearnedToday;
  final VoidCallback onTap;

  /// The tighter variant used inside the season block on Главная.
  final bool compact;

  const DailyQuestCard({
    super.key,
    required this.pointsPerLearnedWord,
    required this.wordsLearnedToday,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final chipSize = compact ? 44.0 : 52.0;
    return GuyoCard(
      onTap: onTap,
      radius: compact ? AppShapes.rowRadius : AppShapes.cardRadius,
      padding: EdgeInsets.all(compact ? 12 : 16),
      child: Row(
        children: [
          RoundIconChip(
            icon: Icons.local_fire_department_rounded,
            size: chipSize,
            gradient: AppColors.dailyQuestGradient,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr('Квест дня'),
                  style: TextStyle(
                    fontSize: compact ? 13 : 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tr('Изучай новые слова'),
                  style: TextStyle(fontSize: compact ? 12.5 : 13.5, color: AppColors.secondaryText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  wordsLearnedToday == 0
                      ? tr('Сегодня пока ни одного')
                      : tr('Сегодня изучено: {0}', [wordsLearnedToday]),
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.primary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          RewardBadge(points: pointsPerLearnedWord),
        ],
      ),
    );
  }
}


/// A section title on Главная: short, bold, no decoration.
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppColors.primaryDark));
}
