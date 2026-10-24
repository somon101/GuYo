import 'dart:async';

import '../l10n/l10n.dart';
import '../widgets/guyo_ui.dart';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/dictionary.dart';
import '../models/language.dart';
import '../theme/app_colors.dart';
import 'home_dashboard_screen.dart';
import 'lessons_screen.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';
import 'practice_screen.dart';
import 'profile_screen.dart';
import 'rating_screen.dart';
import 'economy_screens.dart';
import '../services/push_service.dart';
import 'topics_screen.dart';
import '../widgets/skeleton.dart';

/// The app's main hub, reached right after login.
///
/// Replaces the old "Выйти" button in the top bar with a language switcher:
/// picking a language selects the matching Dictionary (by `Dictionary.
/// language`), and that selection drives every feature reachable from the
/// main menu below. Logging out is still available, just tucked into the
/// overflow menu instead of sitting in the main bar.
///
/// The switcher's option list is never hardcoded: it's built purely from
/// whatever GET /dictionaries returns, and the backend is the one and only
/// place that decides which dictionaries are published -- a regular user's
/// token never gets a draft back at all (see dictionaries.py's
/// `_visible_to`), so this screen doesn't need to (and must not try to)
/// second-guess publish status on its own.
///
/// Bottom nav: "Главная" (HomeDashboardScreen -- the greeting and the
/// season-quests block), "Уроки" (LessonsScreen -- the sequential lesson
/// chain), "Практика" (PracticeScreen -- self-directed drills over
/// already-learned words/phrases, independent of lesson order), "Рейтинг"
/// (RatingScreen -- the user's own-rank leaderboard, never
/// dictionary-scoped) and "Профиль". Switching tabs never touches the
/// language selection above; every dictionary-scoped tab just renders
/// against whichever one is currently selected.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // Plain state fields, not a FutureBuilder -- see _refreshDictionariesInBackground
  // for why: driving the tab tree off a FutureBuilder's own `future`
  // identity meant EVERY reassignment (including a silent background
  // refresh) forced that builder through ConnectionState.waiting for at
  // least one frame, which tore down and rebuilt the entire IndexedStack
  // below -- destroying every tab's State (Профиль's in-progress avatar
  // upload included) even though nothing about the dictionary list itself
  // had actually changed.
  bool _isLoading = true;
  Object? _loadError;
  List<GuyoDictionary> _dictionaries = [];
  GuyoDictionary? _selectedDictionary;
  // Языки для переключателя на главном экране и текущая пара «родной ->
  // изучаемый». Оба языка живут на сервере: список языков правится в админке,
  // пара — в профиле человека.
  List<GuyoLanguage> _languages = [];
  String _nativeLanguage = 'tg';
  String? _learningLanguage;
  int _selectedTabIndex = 0;
  // Lets the app bar's own settings gear (shown only while Профиль is
  // the active tab) open that screen's settings sheet -- the sheet and
  // everything in it still belong entirely to ProfileScreen.
  final GlobalKey<ProfileScreenState> _profileKey =
      GlobalKey<ProfileScreenState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ApiClient.instance.logEvent('app_opened');
    _loadDictionaries();
    // Every way into the app (login, sign-up, an already-saved session)
    // lands here, so this is the one place the phone is registered.
    PushService.instance.registerCurrentUser();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Achievements are deliberately NOT celebrated here any more: the
      // celebration belongs to the end of a lesson, right after its results
      // (see LessonResultsScreen). Popping up on the home screen is what made
      // it appear "everywhere", out of context.
      await _askTopicsOnce();
    });
  }

  /// Accounts that have never picked their topics are asked once, right
  /// after opening the app. Skipping saves an empty choice, so it never
  /// comes back; the choice stays editable in settings.
  static bool _topicsAsked = false;

  Future<void> _askTopicsOnce() async {
    if (_topicsAsked) return;
    _topicsAsked = true;
    try {
      final profile = await ApiClient.instance.fetchMyProfile();
      if (profile.learningTopics != null || !mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const TopicsScreen(initial: [], firstTime: true),
          fullscreenDialog: true,
        ),
      );
    } catch (_) {
      _topicsAsked = false; // try again next time the home screen opens
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // "resumed" also fires after the image picker or a permission dialog;
  // only a real return (away for over a minute) counts as opening the app.
  DateTime? _pausedAt;

  void _logReturn() {
    final pausedAt = _pausedAt;
    _pausedAt = null;
    if (pausedAt != null &&
        DateTime.now().difference(pausedAt) > const Duration(minutes: 1)) {
      ApiClient.instance.logEvent('app_opened');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // An admin can publish/unpublish a dictionary at any time from Admin
    // Web while this app is just sitting in the background. Re-check what's
    // published as soon as the user comes back to it, rather than only on
    // the next cold start -- but silently: returning from ANY external
    // Activity (the image picker included, not just switching apps) fires
    // this same "resumed" transition, so it must never reset or rebuild
    // whatever tab is already on screen.
    if (state == AppLifecycleState.paused) _pausedAt = DateTime.now();
    if (state == AppLifecycleState.resumed) {
      _refreshDictionariesInBackground();
      _logReturn();
    }
  }

  /// The real, user-visible load -- shows the loading/error states below.
  /// Used for the initial load and for the explicit "Повторить"/"Проверить
  /// снова" retry buttons, both cases where there is no tab content mounted
  /// yet to lose anyway.
  Future<void> _loadDictionaries() async {
    // Last launch's list: open on it at once and refresh quietly.
    final kept = _dictionaries.isEmpty
        ? ApiClient.instance.cachedDictionaries()
        : null;
    if (kept != null && kept.isNotEmpty) {
      setState(() {
        _dictionaries = kept;
        _isLoading = false;
        _loadError = null;
      });
      _refreshDictionariesInBackground();
      unawaited(_loadLanguages());
      return;
    }
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final fresh = await ApiClient.instance.fetchDictionaries();
      if (!mounted) return;
      setState(() {
        _dictionaries = fresh;
        _isLoading = false;
      });
      unawaited(_loadLanguages());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _isLoading = false;
      });
    }
  }

  /// Языки для переключателя и текущую пару «родной -> изучаемый».
  ///
  /// Молча, если не доехало: переключатель появится, когда данные придут, а
  /// человек в это время уже видит контент.
  Future<void> _loadLanguages() async {
    try {
      final languages = await ApiClient.instance.fetchLanguages();
      final profile = await ApiClient.instance.fetchMyProfile();
      if (!mounted) return;
      // Какие языки предлагать в переключателе ИНТЕРФЕЙСА, решает база: язык с
      // непереведёнными строками из него убирается без новой сборки.
      setUiLanguagesReady(languages.where((l) => l.uiReady).map((l) => l.code));
      setState(() {
        _languages = languages;
        _nativeLanguage = profile.translationLanguage;
        _learningLanguage = profile.learningLanguage ?? _dictionaryLanguage;
      });
      // A language this person uses was unpublished (something is missing in
      // it): ask them to pick another one, once per launch.
      if (profile.languageUnavailable.isNotEmpty && !_askedLanguageAgain) {
        _askedLanguageAgain = true;
        unawaited(_askForAnotherLanguage(profile.languageUnavailable));
      }
    } catch (_) {
      // Тихо -- см. выше.
    }
  }

  bool _askedLanguageAgain = false;

  /// The language this person learns (or reads hints in) is no longer
  /// available: one sheet per such language, with the published ones to pick.
  Future<void> _askForAnotherLanguage(List<String> which) async {
    for (final kind in which) {
      if (!mounted) return;
      final learning = kind == 'learning';
      final options = _languages
          .where(
            (l) => learning
                ? l.learnable && l.code != _nativeLanguage
                : l.nativeOk && l.code != _learningLanguage,
          )
          .toList();
      if (options.isEmpty) continue;
      final picked = await showModalBottomSheet<GuyoLanguage>(
        context: context,
        isDismissible: false,
        enableDrag: false,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Text(
                  learning
                      ? tr(
                          'Этот язык сейчас недоступен для изучения. Выберите другой',
                        )
                      : tr(
                          'Этот язык перевода сейчас недоступен. Выберите другой',
                        ),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final l in options)
                ListTile(
                  title: Text(l.label),
                  onTap: () => Navigator.of(context).pop(l),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (picked == null || !mounted) continue;
      if (learning) {
        await _selectLearningLanguage(picked);
      } else {
        try {
          final saved = await ApiClient.instance.updateMyProfile(
            translationLanguage: picked.code,
          );
          ApiClient.instance.forgetCachedContent();
          if (mounted)
            setState(() => _nativeLanguage = saved.translationLanguage);
          await _refreshDictionariesInBackground();
        } catch (_) {
          // Asked again on the next launch.
        }
      }
    }
  }

  /// Язык словаря: на нём контент, пока человек не выбрал изучаемый сам.
  String get _dictionaryLanguage => _selectedDictionary?.language ?? 'ru';

  /// Что можно изучать: всё, КРОМЕ текущего родного языка. Иначе подсказка была
  /// бы на том же языке, что и ответ, -- такой вариант не показываем вовсе.
  List<GuyoLanguage> get _learningOptions => _languages
      .where(
        (language) => language.code != _nativeLanguage && language.learnable,
      )
      .toList();

  /// Смена изучаемого языка: сохраняем в профиле, сбрасываем кэш урока и слов
  /// (они были на прежнем языке) и перечитываем контент.
  Future<void> _selectLearningLanguage(GuyoLanguage language) async {
    if (language.code == _learningLanguage) return;
    final previous = _learningLanguage;
    setState(() => _learningLanguage = language.code);
    try {
      final saved = await ApiClient.instance.updateMyProfile(
        learningLanguage: language.code,
      );
      ApiClient.instance.forgetCachedContent();
      if (!mounted) return;
      setState(() {
        _nativeLanguage = saved.translationLanguage;
        _learningLanguage = saved.learningLanguage ?? language.code;
      });
      await _refreshDictionariesInBackground();
    } catch (_) {
      if (mounted) setState(() => _learningLanguage = previous);
    }
  }

  /// Refreshes the dictionary list on app resume without ever touching
  /// `_isLoading`/`_loadError` or otherwise disturbing whatever tab is
  /// currently mounted -- only applies the new list (if the fetch
  /// succeeds) once it's actually in hand. A failure here (a momentary
  /// network blip right as the app resumes, say) is silently ignored: the
  /// user is already looking at a perfectly good previous list, and the
  /// next resume or explicit retry will pick up the real one.
  Future<void> _refreshDictionariesInBackground() async {
    if (_isLoading) return;
    try {
      final fresh = await ApiClient.instance.fetchDictionaries();
      if (!mounted) return;
      setState(() => _dictionaries = fresh);
    } catch (_) {
      // Intentionally silent -- see doc comment above.
    }
  }

  Future<void> _logout() async {
    await PushService.instance.unregisterCurrentUser();
    await ApiClient.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  /// One Dictionary per distinct language, in first-seen order. If the
  /// system ever has more than one dictionary for the same language, the
  /// switcher still only offers one entry per language and picks the first
  /// match -- there's exactly one dictionary per language in the data
  /// today, and nothing here assumes otherwise.
  List<GuyoDictionary> _languageOptions(List<GuyoDictionary> dictionaries) {
    final seen = <String>{};
    final options = <GuyoDictionary>[];
    for (final d in dictionaries) {
      if (seen.add(d.language)) options.add(d);
    }
    return options;
  }

  /// Picks which dictionary should be "current" out of the latest set of
  /// published options: keeps the existing selection if it's still
  /// available, otherwise falls back to the first option -- e.g. because
  /// an admin just unpublished the one the user had open. Returns null
  /// when there's nothing published at all.
  GuyoDictionary? _resolveSelection(List<GuyoDictionary> options) {
    if (options.isEmpty) return null;
    final current = _selectedDictionary;
    if (current != null) {
      for (final option in options) {
        if (option.language == current.language) return option;
      }
    }
    return options.first;
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const SkeletonDashboard();
    }
    if (_loadError != null) {
      // A 401 means the stored token itself is dead (expired, or left over
      // from a different backend/build) -- ApiClient has already cleared it
      // by this point, so retrying the same request would just 401 again
      // forever. Send the user back to a real login instead of trapping
      // them in that loop.
      final error = _loadError;
      final sessionExpired = error is ApiException && error.statusCode == 401;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                sessionExpired
                    ? tr('Сессия истекла')
                    : tr('Не удалось загрузить словари'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: sessionExpired ? _logout : _loadDictionaries,
                child: Text(
                  sessionExpired ? tr('Войти заново') : tr('Повторить'),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final options = _languageOptions(_dictionaries);
    final selected = _resolveSelection(options);
    if (selected == null) {
      // No published content at all -- a clean, explicit state, not an
      // error and not a guess at what might be there.
      return GuyoEmptyState(
        icon: Icons.translate_rounded,
        title: tr('Пока нет доступных словарей'),
        message: tr('Скоро здесь появятся языки для изучения.'),
        actionLabel: tr('Проверить снова'),
        onAction: _loadDictionaries,
      );
    }
    _selectedDictionary = selected;
    GuyoDictionary.studyLanguage = selected.language;

    // Keying by dictionary id makes each tab's content rebuild fresh
    // whenever the selected language changes. IndexedStack (not a simple
    // `_selectedTabIndex == 0 ? … : …`) keeps every tab's state alive across
    // switches -- AND across a background dictionary refresh, now that this
    // whole method only ever runs again because of a real setState, never
    // because a FutureBuilder's `future` identity changed -- so leaving
    // "Уроки" mid-round, or Профиль mid avatar-upload, and coming back to
    // it doesn't lose anything.
    return IndexedStack(
      index: _selectedTabIndex,
      children: [
        HomeDashboardScreen(
          key: ValueKey('home-${selected.id}'),
          dictionary: selected,
          // "Квест дня" is carried out in Уроки, which is a sibling tab
          // rather than a route -- so the dashboard asks the shell to
          // switch instead of pushing anything.
          onOpenLessons: () => setState(() => _selectedTabIndex = 1),
          onOpenProfile: () => setState(() => _selectedTabIndex = 4),
          onOpenRating: () => setState(() => _selectedTabIndex = 3),
        ),
        LessonsScreen(
          key: ValueKey('lessons-${selected.id}'),
          dictionary: selected,
        ),
        PracticeScreen(
          key: ValueKey('practice-${selected.id}'),
          dictionary: selected,
        ),
        // Neither tab below is dictionary-scoped at all (identity/
        // achievements/rating are per-user, not per-language) -- kept in
        // the same IndexedStack purely for consistency with the other
        // tabs; no ValueKey needed since nothing about either depends on
        // `selected`.
        const RatingScreen(),
        // No ValueKey on purpose: the profile is per-user, not
        // per-language, so switching languages must not rebuild it. The
        // dictionary is passed only so its "Мои слова" card opens the
        // right language's words.
        ProfileScreen(
          key: _profileKey,
          dictionary: selected,
          onOpenLessons: () => setState(() => _selectedTabIndex = 1),
        ),
      ],
    );
  }

  Widget _buildLanguageSwitcher() {
    final options = _learningOptions;
    if (options.isEmpty) return const SizedBox.shrink();
    final current = _languages.firstWhere(
      (language) => language.code == _learningLanguage,
      orElse: () => options.first,
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 112),
      child: _LanguageSwitcher(
        current: current,
        options: options,
        onSelected: (language) => unawaited(_selectLearningLanguage(language)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Профиль is the one tab that isn't dictionary-scoped at all, so the
    // language switcher is meaningless there -- it shows its own settings
    // gear instead (which opens ProfileScreen's own sheet, logout
    // included), matching that screen's design.
    final isProfileTab = _selectedTabIndex == 4;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 64,
        titleSpacing: 16,
        title: Row(
          children: [
            const GuyoWordmark(),
            const SizedBox(width: 5),
            if (!isProfileTab)
              Expanded(child: Center(child: _buildLanguageSwitcher()))
            else
              const Spacer(),
            if (isProfileTab)
              IconButton(
                tooltip: tr('Настройки'),
                icon: Icon(Icons.settings_outlined, color: AppColors.primary),
                onPressed: () => _profileKey.currentState?.openSettings(),
              )
            else ...[
              const SizedBox(width: 6),
              _EconomyHeaderButton(
                onOpen: () async {
                  await openEconomy(context);
                },
              ),
              const _NotificationsButton(),
            ],
          ],
        ),
      ),
      body: _buildBody(),
      bottomNavigationBar: FloatingNavBar(
        selectedIndex: _selectedTabIndex,
        onSelected: (index) => setState(() => _selectedTabIndex = index),
        items: [
          NavItemData(Icons.grid_view_rounded, tr('Главная')),
          NavItemData(Icons.menu_book_rounded, tr('Уроки')),
          NavItemData(Icons.bolt_rounded, tr('Практика')),
          NavItemData(Icons.bar_chart_rounded, tr('Рейтинг')),
          NavItemData(Icons.person_rounded, tr('Профиль')),
        ],
      ),
    );
  }
}

class NavItemData {
  final IconData icon;
  final String label;
  const NavItemData(this.icon, this.label);
}

/// The bottom bar: a compact pill that floats above the canvas. Icons only,
/// no captions: the chosen tab is a round brand-coloured button, the others
/// are quiet grey icons spread evenly. A long press shows the tab's name.
class FloatingNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<NavItemData> items;

  const FloatingNavBar({
    required this.selectedIndex,
    required this.onSelected,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.canvas,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: AppColors.dark ? 0.35 : 0.08,
                  ),
                  blurRadius: 22,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < items.length; i++)
                  NavButton(
                    data: items[i],
                    selected: i == selectedIndex,
                    onTap: () => onSelected(i),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NavButton extends StatelessWidget {
  final NavItemData data;
  final bool selected;
  final VoidCallback onTap;

  const NavButton({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: data.label,
      child: Tooltip(
        message: data.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? AppColors.primary : Colors.transparent,
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              data.icon,
              size: selected ? 22 : 24,
              color: selected ? Colors.white : AppColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _EconomyHeaderButton extends StatefulWidget {
  final Future<void> Function() onOpen;
  const _EconomyHeaderButton({required this.onOpen});
  @override
  State<_EconomyHeaderButton> createState() => _EconomyHeaderButtonState();
}

class _EconomyHeaderButtonState extends State<_EconomyHeaderButton> {
  int? _diamonds;
  @override
  void initState() {
    super.initState();
    ApiClient.instance.economyBalance.addListener(_balanceChanged);
    _load();
  }

  @override
  void dispose() {
    ApiClient.instance.economyBalance.removeListener(_balanceChanged);
    super.dispose();
  }

  void _balanceChanged() {
    if (mounted)
      setState(() => _diamonds = ApiClient.instance.economyBalance.value);
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.instance.fetchEconomy();
      if (mounted) setState(() => _diamonds = data['diamonds'] as int? ?? 0);
    } catch (_) {
      /* keep the balance placeholder until online data arrives */
    }
  }

  Future<void> _open() async {
    await widget.onOpen();
    _load();
  }

  /// One pill for the whole wallet: the diamond balance, a hairline, and
  /// the shop/gifts entry -- both halves open the same screen.
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: tr('Магазин и подарки'),
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: _open,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.diamond_rounded, size: 18, color: AppColors.primary),
            const SizedBox(width: 5),
            Text(
              _diamonds?.toString() ?? '—',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.primaryDark,
              ),
            ),
            Container(
              width: 1,
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: AppColors.separator,
            ),
            Icon(
              Icons.card_giftcard_rounded,
              size: 19,
              color: AppColors.danger,
            ),
          ],
        ),
      ),
    ),
  );
}

/// The notifications bell in the top bar.
///
/// Purely the design's own element for now: GuYo has no notification
/// system, no API and no unread state behind it, so it deliberately shows
/// no badge -- a permanent red dot would claim something the app cannot
/// actually tell the user. Tapping it says so plainly rather than doing
/// nothing at all.
/// The bell in the top bar: opens the inbox, and carries a dot while
/// anything in it is unread.
///
/// The count comes from its own cheap endpoint rather than the whole
/// inbox, and is re-read whenever the app comes back to the foreground or
/// the user returns from the notifications screen -- a message sent while
/// the app was open should not need a restart to show up.
class _NotificationsButton extends StatefulWidget {
  const _NotificationsButton();

  @override
  State<_NotificationsButton> createState() => _NotificationsButtonState();
}

class _NotificationsButtonState extends State<_NotificationsButton>
    with WidgetsBindingObserver {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PushService.instance.foregroundMessages.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PushService.instance.foregroundMessages.removeListener(_refresh);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final count = await ApiClient.instance.fetchUnreadNotificationCount();
      if (!mounted) return;
      setState(() => _unread = count);
    } catch (_) {
      // A failed count must never break the app bar -- the dot simply
      // stays as it was until the next refresh.
    }
  }

  Future<void> _open() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
    // Opening the inbox marks everything read, so the dot is re-checked
    // rather than assumed cleared.
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Semantics(
        button: true,
        label: tr('Уведомления'),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _open,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.notifications_none_rounded,
                  size: 22,
                  color: AppColors.primaryDark,
                ),
                if (_unread > 0)
                  Positioned(
                    right: 9,
                    top: 9,
                    child: Container(
                      // Keyed so a test can assert the indicator itself
                      // rather than a coloured box -- same convention the
                      // exercise screens use for their own hooks.
                      key: const ValueKey('notifications-unread-dot'),
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4056),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.surface,
                          width: 1.5,
                        ),
                      ),
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

/// The learning-language switcher in the app bar: a soft pill with the
/// language's short code in a tinted badge, its name and a small chevron;
/// the menu lists the languages as rows with a check on the current one.
/// With only one language there is nothing to switch, so no chevron and
/// no menu.
class _LanguageSwitcher extends StatelessWidget {
  final GuyoLanguage current;
  final List<GuyoLanguage> options;
  final ValueChanged<GuyoLanguage> onSelected;

  const _LanguageSwitcher({
    required this.current,
    required this.options,
    required this.onSelected,
  });

  Widget _badge(GuyoLanguage d, {bool selected = true}) => Container(
    width: 26,
    height: 22,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: selected
          ? AppColors.primary
          : AppColors.primary.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      d.code.toUpperCase(),
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.3,
        color: selected ? Colors.white : AppColors.primary,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final canSwitch = options.length > 1;
    final pill = Container(
      height: 36,
      padding: EdgeInsets.fromLTRB(6, 0, canSwitch ? 6 : 12, 0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.separator),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _badge(current),
          const SizedBox(width: 8),
          Text(
            current.label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryDark,
            ),
          ),
          if (canSwitch) ...[
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: AppColors.secondaryText,
            ),
          ],
        ],
      ),
    );
    if (!canSwitch) return Center(child: pill);

    return PopupMenuButton<GuyoLanguage>(
      key: const ValueKey('language-switcher'),
      tooltip: tr('Выбрать язык'),
      onSelected: onSelected,
      offset: const Offset(0, 44),
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem(
            value: option,
            height: 46,
            child: Row(
              children: [
                _badge(option, selected: option.code == current.code),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    option.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: option.code == current.code
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
                if (option.code == current.code)
                  Icon(Icons.check_rounded, size: 18, color: AppColors.primary),
              ],
            ),
          ),
      ],
      child: Center(child: pill),
    );
  }
}
