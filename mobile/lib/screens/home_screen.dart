import '../l10n/l10n.dart';
import '../widgets/guyo_ui.dart';
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/dictionary.dart';
import '../theme/app_colors.dart';
import 'home_dashboard_screen.dart';
import 'lessons_screen.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';
import 'practice_screen.dart';
import 'profile_screen.dart';
import 'rating_screen.dart';
import '../services/push_service.dart';
import 'topics_screen.dart';
import '../widgets/skeleton.dart';
import '../widgets/achievement_celebration.dart';

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
  int _selectedTabIndex = 0;
  // Lets the app bar's own settings gear (shown only while Профиль is
  // the active tab) open that screen's settings sheet -- the sheet and
  // everything in it still belong entirely to ProfileScreen.
  final GlobalKey<ProfileScreenState> _profileKey = GlobalKey<ProfileScreenState>();

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
      await _askTopicsOnce();
      // Anything earned but not yet celebrated -- including achievements
      // already due on this login -- is shown once, right away.
      if (mounted) await celebrateNewAchievements(context);
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
        MaterialPageRoute(builder: (_) => const TopicsScreen(initial: [], firstTime: true), fullscreenDialog: true),
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
    if (pausedAt != null && DateTime.now().difference(pausedAt) > const Duration(minutes: 1)) {
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
    final kept = _dictionaries.isEmpty ? ApiClient.instance.cachedDictionaries() : null;
    if (kept != null && kept.isNotEmpty) {
      setState(() {
        _dictionaries = kept;
        _isLoading = false;
        _loadError = null;
      });
      _refreshDictionariesInBackground();
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _isLoading = false;
      });
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
                sessionExpired ? tr('Сессия истекла') : tr('Не удалось загрузить словари'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: sessionExpired ? _logout : _loadDictionaries,
                child: Text(sessionExpired ? tr('Войти заново') : tr('Повторить')),
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
        LessonsScreen(key: ValueKey('lessons-${selected.id}'), dictionary: selected),
        PracticeScreen(key: ValueKey('practice-${selected.id}'), dictionary: selected),
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
        titleSpacing: 16,
        title: const _GuyoWordmark(),
        actions: [
          if (isProfileTab)
            IconButton(
              tooltip: tr('Настройки'),
              icon: Icon(Icons.settings_outlined, color: AppColors.primary),
              onPressed: () => _profileKey.currentState?.openSettings(),
            )
          else ...[
          Builder(
            builder: (context) {
              final options = _languageOptions(_dictionaries);
              final current = _resolveSelection(options);
              if (current == null) {
                // Nothing published -- no switcher to show at all, not even
                // a disabled one with a made-up language in it.
                return const SizedBox.shrink();
              }
              _selectedDictionary = current;

              return _LanguageSwitcher(
                current: current,
                options: options,
                onSelected: (d) => setState(() => _selectedDictionary = d),
              );
            },
          ),
          const _NotificationsButton(),
          ],
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          height: 64,
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.primary.withValues(alpha: 0.12),
          indicatorShape: const StadiumBorder(),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: states.contains(WidgetState.selected) ? AppColors.primary : AppColors.secondaryText,
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              size: 22,
              color: states.contains(WidgetState.selected) ? AppColors.primary : AppColors.secondaryText,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _selectedTabIndex,
          onDestinationSelected: (index) => setState(() => _selectedTabIndex = index),
          destinations: [
            NavigationDestination(icon: Icon(Icons.home_outlined), label: tr('Главная')),
            NavigationDestination(icon: Icon(Icons.auto_stories_outlined), label: tr('Уроки')),
            NavigationDestination(icon: Icon(Icons.fitness_center_outlined), label: tr('Практика')),
            NavigationDestination(icon: Icon(Icons.leaderboard_outlined), label: tr('Рейтинг')),
            NavigationDestination(icon: Icon(Icons.person_outline), label: tr('Профиль')),
          ],
        ),
      ),
    );
  }
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

class _NotificationsButtonState extends State<_NotificationsButton> with WidgetsBindingObserver {
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
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    // Opening the inbox marks everything read, so the dot is re-checked
    // rather than assumed cleared.
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tr('Уведомления'),
      onPressed: _open,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.notifications_none_rounded, color: AppColors.primaryDark),
          if (_unread > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                // Keyed so a test can assert the indicator itself rather
                // than a coloured box -- same convention the exercise
                // screens use for their own hooks.
                key: const ValueKey('notifications-unread-dot'),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4056),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.canvas, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The "GuYo" wordmark: the same text as before, just painted with the
/// brand's own indigo-to-violet gradient instead of a flat color, so the
/// app bar reads as a logo rather than a plain title. Shown on every tab.
class _GuyoWordmark extends StatelessWidget {
  const _GuyoWordmark();

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: [AppColors.primary, Color(0xFF8B5CF6)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(bounds),
      child: const Text(
        'GuYo',
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.5,
          // Painted over by the shader above -- must stay opaque white for
          // the gradient to show through at full strength.
          color: Colors.white,
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
  final GuyoDictionary current;
  final List<GuyoDictionary> options;
  final ValueChanged<GuyoDictionary> onSelected;

  const _LanguageSwitcher({required this.current, required this.options, required this.onSelected});

  Widget _badge(GuyoDictionary d, {bool selected = true}) => Container(
        width: 26,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          d.language.toUpperCase(),
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
            current.languageLabel,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
          ),
          if (canSwitch) ...[
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.secondaryText),
          ],
        ],
      ),
    );
    if (!canSwitch) return Center(child: pill);

    return PopupMenuButton<GuyoDictionary>(
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
                _badge(option, selected: option.id == current.id),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    option.languageLabel,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: option.id == current.id ? FontWeight.w700 : FontWeight.w500,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
                if (option.id == current.id) Icon(Icons.check_rounded, size: 18, color: AppColors.primary),
              ],
            ),
          ),
      ],
      child: Center(child: pill),
    );
  }
}
