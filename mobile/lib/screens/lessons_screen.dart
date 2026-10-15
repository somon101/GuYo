import 'dart:async';
import '../l10n/l10n.dart';
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../services/lesson_scoring.dart';
import '../services/pending_answers.dart';
import '../services/session_cache.dart';
import '../models/dictionary.dart';
import '../models/lesson.dart';
import '../theme/app_colors.dart';
import 'lesson_create_screen.dart';
import 'lesson_detail_screen.dart';
import 'lesson_run_screen.dart';
import '../widgets/in_app_banner.dart';
import '../widgets/skeleton.dart';

/// "Уроки": the new primary progress system's own tab. Shows this
/// dictionary's FULL, permanent lesson history as a flat list of cards --
/// every lesson the user has ever created, each with its own real status
/// (never a locally-invented one) -- rendered NEWEST first (highest
/// number at the top): the backend's own list (GET .../lessons) stays
/// oldest-first as its stable order, this screen just reverses it for
/// display, with one extra unlocked card leading at the top for creating
/// the next lesson once the current last one is fully complete (or there
/// isn't one yet). Lessons are never deleted or replaced (see the
/// backend's Lesson model): completing one just reveals the next card, it
/// never removes the one before it.
///
/// This screen owns none of the actual lesson mechanics -- word selection,
/// exercises, scoring, the learning threshold -- all of that is unchanged
/// and lives in LessonDetailScreen/LessonCreateScreen/LessonRunScreen/the
/// exercise screens. This is purely "what lessons exist and in what order", always
/// re-fetched from the backend, never assembled from local state.
class LessonsScreen extends StatefulWidget {
  final GuyoDictionary dictionary;
  const LessonsScreen({super.key, required this.dictionary});

  @override
  State<LessonsScreen> createState() => _LessonsScreenState();
}

class _LessonsScreenState extends State<LessonsScreen> {
  bool _isLoading = true;
  String? _loadError;
  List<LessonSummary> _lessons = [];

  String get _cacheKey => 'lessons-${widget.dictionary.id}';

  @override
  void initState() {
    super.initState();
    var cached = SessionCache.get<List<LessonSummary>>(_cacheKey);
    if (cached == null) {
      // Last launch's list, kept on the device.
      cached = ApiClient.instance.cachedLessons(widget.dictionary.id);
      if (cached != null) SessionCache.put(_cacheKey, cached);
    }
    if (cached != null) {
      _lessons = cached;
      _isLoading = false;
    }
    // The moment the device's own pass work reaches the server, this list is
    // reloaded by itself: «Синхронизируется с сервером…» turns into the confirmed
    // result without the user reloading anything (see ApiClient.syncTick).
    ApiClient.instance.syncTick.addListener(_onSynced);
    _load();
  }

  void _onSynced() {
    if (mounted) unawaited(_load());
  }

  @override
  void dispose() {
    ApiClient.instance.syncTick.removeListener(_onSynced);
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final hasData = SessionCache.get<List<LessonSummary>>(_cacheKey) != null;
    setState(() {
      // Data already on screen stays there while it refreshes.
      _isLoading = !hasData;
      _loadError = null;
    });
    try {
      final lessons = await ApiClient.instance.fetchLessons(widget.dictionary.id);
      SessionCache.put(_cacheKey, lessons);
      unawaited(_prepareNext(lessons));
      if (!mounted) return;
      setState(() {
        _lessons = lessons;
        _isLoading = false;
      });
      // A pass that is still on the device goes over in the background (see
      // fetchLessons); one quiet re-check a few seconds later is what turns
      // "проверяем результаты" back into "можно создавать урок".
      if (_awaitingCheckLessonId != null) {
        Future<void>.delayed(const Duration(seconds: 4), () {
          if (mounted) setState(() {});
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (!hasData) _loadError = tr('Не удалось загрузить уроки');
      });
    }
  }

  Future<void> _openLesson(int lessonId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LessonDetailScreen(lessonId: lessonId)),
    );
    await _load();
  }

  /// Plays [lesson] start to finish (LessonRunScreen), then refreshes the
  /// chain -- the lesson may have just been completed.
  Future<void> _runLesson(Lesson lesson) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => LessonRunScreen.forLesson(lesson)));
    await _load();
  }

  /// The lesson a user is about to continue, fetched and its exercises
  /// prepared in the background -- "Продолжить" then starts at once.
  Future<void> _prepareNext(List<LessonSummary> lessons) async {
    final next = lessons.where((l) => !l.isCompleted).firstOrNull;
    if (next == null) return;
    try {
      final lesson = await ApiClient.instance.fetchLesson(next.id);
      SessionCache.put('lesson-${next.id}', lesson);
      await prepareLessonAhead(lesson);
    } catch (_) {
      // Best effort only.
    }
  }

  /// "Продолжить" on the in-progress card: straight into the exercises,
  /// with no stop at the lesson's own screen.
  Future<void> _continueLesson(int lessonId) async {
    Lesson? lesson = SessionCache.take<Lesson>('lesson-$lessonId');
    // A network blip shouldn't stop the lesson: one quiet second try.
    for (var attempt = 0; lesson == null && attempt < 2; attempt++) {
      try {
        lesson = await ApiClient.instance.fetchLesson(lessonId);
      } catch (_) {
        if (attempt == 0) await Future<void>.delayed(const Duration(milliseconds: 800));
      }
    }
    if (lesson == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('Не удалось открыть урок. Проверьте интернет.')),
          action: SnackBarAction(label: tr('Повторить'), onPressed: () => _continueLesson(lessonId)),
        ),
      );
      return;
    }
    if (!mounted) return;
    await _runLesson(lesson);
  }

  /// The lesson whose pass this device scored for itself and the server has not
  /// confirmed -- or null when everything is settled.
  ///
  /// Two things count, and BOTH matter for the card that offers to create the
  /// next lesson:
  ///  * work still queued to be handed over ([PendingAnswers]);
  ///  * a pass that went over but whose result the device has not had confirmed
  ///    yet (the local score copy in [LessonScoreOverlay]). Without this one, the
  ///    cached list -- taken before the pass, so it still shows the PREVIOUS
  ///    lesson as the newest -- offered "Создать урок 21" for a lesson the server
  ///    already had, and the lesson the user had just finished looked unpassed.
  ///
  /// The hand-over happens by itself (every 30 seconds, and whenever this list is
  /// loaded), so the state is short-lived.
  int? get _awaitingCheckLessonId {
    // The QUEUE first, and by its own lesson id: it knows which lesson its work
    // belongs to, while the list on screen may be older than that lesson. This is
    // exactly how "Доступен для создания Урок 31" appeared for a lesson that
    // already existed and was half-played: the cached list was taken before it was
    // created, so the loop below never saw it.
    for (final action in PendingAnswers.all) {
      final id = action['lesson_id'];
      if (id is int) return id;
    }
    for (final lesson in _lessons) {
      if (LessonScoreOverlay.scoresFor(lesson.id).isNotEmpty) return lesson.id;
    }
    return null;
  }

  /// How many of this lesson's words are at their level once the pass THIS device
  /// scored for itself is counted -- or null when there is nothing local to add.
  ///
  /// The server's own list is short by exactly that work, so a lesson played with
  /// no network read "Изучено 0 из 5" with its words already learned, right next
  /// to a note saying the pass was done.
  int? _locallyLearned(int lessonId) {
    if (LessonScoreOverlay.scoresFor(lessonId).isEmpty) return null;
    final full = ApiClient.instance.cachedLesson(lessonId);
    final rules = ApiClient.instance.cachedExerciseScoring();
    if (full == null || rules == null) return null;
    return LessonScoreOverlay.applied(full, rules).words.where((w) => w.isLearned).length;
  }

  /// Word selection, then -- when "Начать урок" there creates the lesson
  /// -- straight into it.
  Future<void> _createNextLesson() async {
    // Nothing may be created while a pass is still waiting to be checked: the
    // lesson it belongs to is not really finished yet.
    if (_awaitingCheckLessonId != null) {
      InAppBanner.show(
        body: tr('Сначала проверяются результаты прошлого урока'),
        visibleFor: InAppBanner.confirmationVisibleFor,
        opensInbox: false,
      );
      return;
    }
    final lesson = await Navigator.of(context).push<Lesson>(
      MaterialPageRoute(builder: (_) => LessonCreateScreen(dictionary: widget.dictionary)),
    );
    if (lesson != null && mounted) {
      await _runLesson(lesson);
    } else {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Nothing above the chain any more: "Квесты" moved to Главная (a
    // season-wide system was never part of the lesson chain) and "Мои
    // слова" moved to Профиль (the user's own vocabulary belongs with the
    // rest of what they have earned, not inside one lesson list).
    return SafeArea(
      child: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return ListView(
        children: const [SizedBox(height: 520, child: SkeletonList(rows: 6))],
      );
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
                FilledButton(onPressed: _load, child: Text(tr('Повторить'))),
              ],
            ),
          ),
        ],
      );
    }

    final lessons = _lessons;
    // The lesson whose pass is still on the device, waiting to be handed over
    // and checked by the server. Until that happens its results -- and the
    // words it moved -- are not real yet, so no new lesson may be created
    // (mirroring the backend's own creation rule); the way forward is to play
    // that lesson again.
    final awaitingCheckId = _awaitingCheckLessonId;
    final awaitingLesson =
        awaitingCheckId == null ? null : lessons.firstWhere((l) => l.id == awaitingCheckId, orElse: () => lessons.first);
    // A new card is only ever added once the current last lesson is fully
    // complete -- exactly the backend's own creation rule (POST /lessons
    // 409s otherwise), mirrored here purely for what the list displays.
    final canCreateNext = (lessons.isEmpty || lessons.last.isCompleted) && awaitingCheckId == null;
    final nextNumber = lessons.isEmpty ? 1 : lessons.last.number + 1;
    final completedCount = lessons.where((l) => l.isCompleted).length;

    // The backend's own list stays oldest-first (its natural, stable
    // order) -- only the RENDER order is newest-first: the not-yet-created
    // next lesson (if unlocked) leads at the top, then existing lessons
    // counting down from the highest number, so "Урок 3, Урок 2, Урок 1"
    // reads top to bottom instead of the other way around.
    final reversedLessons = lessons.reversed.toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        Text(
          tr('Уроки'),
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
        ),
        const SizedBox(height: 6),
        Text(
          lessons.isEmpty ? tr('Создайте первый урок, чтобы начать') : tr('Пройдено {0} из {1}', [completedCount, lessons.length]),
          style: TextStyle(color: AppColors.secondaryText, fontSize: 14),
        ),
        const SizedBox(height: 22),
        if (canCreateNext)
          _LessonCard(
            state: _LessonCardState.unlocked,
            number: nextNumber,
            title: tr('Урок {0}', [nextNumber]),
            subtitle: lessons.isEmpty ? tr('Создать урок') : tr('Доступен для создания'),
            progress: null,
            onTap: _createNextLesson,
          ),
        // ONE card per lesson, always -- the lesson whose pass is still waiting
        // to be confirmed gets no card of its own, or the same lesson shows up
        // twice (which is exactly what happened). Only what its own card says
        // changes: passed by the app's own count, all that is missing is the
        // server's confirmation and it says so; not passed, the ordinary
        // "continue and earn the points" card.
        for (final lesson in reversedLessons)
          _LessonCard(
            state: lesson.isCompleted ? _LessonCardState.completed : _LessonCardState.inProgress,
            number: lesson.number,
            title: tr('Урок {0}', [lesson.number]),
            // Waiting for the server's confirmation, with the points already
            // earned: say ONLY that. No percentage and no "continue" -- the
            // device's own numbers have nothing left to add, and offering to
            // carry on made a finished lesson look unfinished.
            subtitle: lesson.id == awaitingLesson?.id && lesson.isCompleted
                ? tr('Синхронизируется с сервером…')
                : tr('Изучено {0} из {1} слов', [
                    _locallyLearned(lesson.id) ?? lesson.learnedCount,
                    lesson.wordCount,
                  ]),
            progress: lesson.id == awaitingLesson?.id && lesson.isCompleted
                ? null
                : (lesson.wordCount == 0
                    ? 0.0
                    : ((_locallyLearned(lesson.id) ?? lesson.learnedCount) / lesson.wordCount).clamp(0.0, 1.0)),
            onTap: () => _openLesson(lesson.id),
            // Points NOT earned: the ordinary "continue and earn them" card.
            // Confirmed complete: no button either. Only the still-unconfirmed
            // one offers a repeat, so nobody is stuck without a network.
            onContinue: lesson.isCompleted
                ? (lesson.id == awaitingLesson?.id ? () => _continueLesson(lesson.id) : null)
                : () => _continueLesson(lesson.id),
          ),
      ],
    );
  }
}

enum _LessonCardState { completed, inProgress, unlocked }

/// One lesson, as a flat, self-contained card -- no connecting line to its
/// neighbors, clearly separated from the page background by its own
/// surface/border/shadow. Colors follow AppColors: indigo/blue for the
/// in-progress lesson (its badge, progress bar, and "Продолжить" button,
/// which jumps straight into the exercise sequence -- see
/// LessonRunScreen), soft green for a completed one, grey
/// for the still-locked "create the next one" card.
class _LessonCard extends StatelessWidget {
  final _LessonCardState state;
  final int number;
  final String title;
  final String subtitle;
  final double? progress;
  final VoidCallback onTap;
  // Only set for an in-progress lesson -- jumps straight into the exercise
  // sequence instead of opening the word-list screen first, same
  // underlying flow as its own "Начать урок"/"Продолжить" button, just
  // reachable without that extra tap.
  final VoidCallback? onContinue;

  const _LessonCard({
    required this.state,
    required this.number,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.onTap,
    this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final bool isActive = state == _LessonCardState.inProgress;
    final Color badgeColor;
    final Color tint;
    switch (state) {
      case _LessonCardState.completed:
        badgeColor = AppColors.success;
        tint = AppColors.success;
      case _LessonCardState.inProgress:
        badgeColor = AppColors.primary;
        tint = AppColors.primary;
      case _LessonCardState.unlocked:
        badgeColor = AppColors.muted;
        tint = AppColors.secondaryText;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: isActive ? AppColors.primary.withValues(alpha: 0.05) : AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: isActive ? AppColors.primary.withValues(alpha: 0.22) : AppColors.cardBorder),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.035), blurRadius: 14, offset: const Offset(0, 5)),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LessonBadge(state: state, color: badgeColor, number: number),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                            ),
                          ),
                          if (state == _LessonCardState.completed)
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(color: AppColors.successLight, shape: BoxShape.circle),
                              child: Icon(Icons.check_rounded, color: AppColors.success, size: 15),
                            )
                          else if (state == _LessonCardState.unlocked)
                            Icon(Icons.add_circle_outline, color: tint, size: 20)
                          else
                            Icon(Icons.chevron_right, color: AppColors.muted, size: 20),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (state == _LessonCardState.completed)
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.successLight,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                tr('Пройден'),
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.success),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${((progress ?? 1) * 100).round()}%',
                              style: TextStyle(fontSize: 13, color: AppColors.secondaryText, fontWeight: FontWeight.w600),
                            ),
                          ],
                        )
                      else if (subtitle == tr('Синхронизируется с сервером…'))
                        // Waiting for the server: a spinner and the note, nothing
                        // else. A percentage here would be the DEVICE's own count
                        // dressed up as the server's, and a button would invite the
                        // user to redo a pass that is already done.
                        Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                            ),
                            const SizedBox(width: 8),
                            Text(subtitle, style: TextStyle(fontSize: 13, color: AppColors.secondaryText)),
                          ],
                        )
                      else
                        Text(subtitle, style: TextStyle(fontSize: 13, color: AppColors.secondaryText)),
                      if (isActive && subtitle != tr('Синхронизируется с сервером…')) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: progress ?? 0,
                                  minHeight: 6,
                                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                                  valueColor: AlwaysStoppedAnimation(AppColors.primary),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${(((progress ?? 0) * 100).round())}%',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
                            ),
                            if (onContinue != null) ...[
                              const SizedBox(width: 10),
                              _ContinueButton(onTap: onContinue!),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The circular lesson-number badge: a solid colored circle, a very soft
/// halo behind it, and -- only for the currently in-progress lesson -- a
/// small, light checkmark marker floating at its top-right corner (purely
/// this position's own visual marker, not a "completed" claim; a locked/
/// unlocked or a truly completed badge never gets one, the completed
/// state already has its own checkmark next to the title instead).
class _LessonBadge extends StatelessWidget {
  final _LessonCardState state;
  final Color color;
  final int number;
  const _LessonBadge({required this.state, required this.color, required this.number});

  @override
  Widget build(BuildContext context) {
    final size = state == _LessonCardState.inProgress ? 60.0 : 52.0;
    return SizedBox(
      width: size + 10,
      height: size + 10,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 5,
            top: 5,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [
                  BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 16, spreadRadius: 1),
                ],
              ),
              alignment: Alignment.center,
              child: state == _LessonCardState.unlocked
                  ? const Icon(Icons.add_rounded, color: Colors.white, size: 24)
                  : Text('$number', style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
            ),
          ),
          if (state == _LessonCardState.inProgress)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: AppColors.successLight,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 2),
                ),
                child: Icon(Icons.check_rounded, color: AppColors.success, size: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ContinueButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Text(
            tr('Продолжить'),
            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
