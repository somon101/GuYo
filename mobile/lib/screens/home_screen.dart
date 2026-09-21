import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/dictionary.dart';
import 'lessons_screen.dart';
import 'login_screen.dart';
import 'main_menu_screen.dart';
import 'practice_screen.dart';

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
/// Bottom nav has three destinations: "Главная" (MainMenuScreen -- whatever
/// doesn't have its own tab, currently just "Словарь"), "Уроки"
/// (LessonsScreen -- the sequential lesson chain) and "Практика"
/// (PracticeScreen -- self-directed drills over already-learned words/
/// phrases, entirely independent of lesson order). Switching tabs never
/// touches the language selection above; every tab just renders against
/// whichever dictionary is currently selected.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late Future<List<GuyoDictionary>> _dictionariesFuture;
  GuyoDictionary? _selectedDictionary;
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dictionariesFuture = ApiClient.instance.fetchDictionaries();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // An admin can publish/unpublish a dictionary at any time from Admin
    // Web while this app is just sitting in the background. Re-check what's
    // published as soon as the user comes back to it, rather than only on
    // the next cold start.
    if (state == AppLifecycleState.resumed) {
      _reloadDictionaries();
    }
  }

  void _reloadDictionaries() {
    setState(() {
      _dictionariesFuture = ApiClient.instance.fetchDictionaries();
    });
  }

  Future<void> _logout() async {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GuYo'),
        actions: [
          FutureBuilder<List<GuyoDictionary>>(
            future: _dictionariesFuture,
            builder: (context, snapshot) {
              final options = _languageOptions(snapshot.data ?? []);
              final current = _resolveSelection(options);
              if (current == null) {
                // Nothing published -- no switcher to show at all, not even
                // a disabled one with a made-up language in it.
                return const SizedBox.shrink();
              }
              _selectedDictionary = current;

              if (options.length == 1) {
                // Exactly one published language: show it plainly, no
                // dropdown affordance since there's nothing to switch to.
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Center(
                    child: Text(current.languageLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                );
              }

              return PopupMenuButton<GuyoDictionary>(
                tooltip: 'Выбрать язык',
                onSelected: (d) => setState(() => _selectedDictionary = d),
                itemBuilder: (context) => [
                  for (final option in options)
                    PopupMenuItem(value: option, child: Text(option.languageLabel)),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(current.languageLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              );
            },
          ),
          PopupMenuButton<String>(
            tooltip: 'Ещё',
            onSelected: (value) {
              if (value == 'logout') _logout();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'logout', child: Text('Выйти')),
            ],
          ),
        ],
      ),
      body: FutureBuilder<List<GuyoDictionary>>(
        future: _dictionariesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            // A 401 means the stored token itself is dead (expired, or left
            // over from a different backend/build) -- ApiClient has already
            // cleared it by this point, so retrying the same request would
            // just 401 again forever. Send the user back to a real login
            // instead of trapping them in that loop.
            final error = snapshot.error;
            final sessionExpired = error is ApiException && error.statusCode == 401;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      sessionExpired ? 'Сессия истекла' : 'Не удалось загрузить словари',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: sessionExpired ? _logout : _reloadDictionaries,
                      child: Text(sessionExpired ? 'Войти заново' : 'Повторить'),
                    ),
                  ],
                ),
              ),
            );
          }
          final options = _languageOptions(snapshot.data ?? []);
          final selected = _resolveSelection(options);
          if (selected == null) {
            // No published content at all -- a clean, explicit state, not
            // an error and not a guess at what might be there.
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Пока нет доступных словарей', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _reloadDictionaries, child: const Text('Проверить снова')),
                  ],
                ),
              ),
            );
          }
          _selectedDictionary = selected;

          // Keying by dictionary id makes each tab's content rebuild fresh
          // whenever the selected language changes. IndexedStack (not a
          // simple `_selectedTabIndex == 0 ? … : …`) keeps both tabs' state
          // alive across switches, so leaving "Уроки" mid-round and coming
          // back to it doesn't lose anything.
          return IndexedStack(
            index: _selectedTabIndex,
            children: [
              MainMenuScreen(key: ValueKey('menu-${selected.id}'), dictionary: selected),
              LessonsScreen(key: ValueKey('lessons-${selected.id}'), dictionary: selected),
              PracticeScreen(key: ValueKey('practice-${selected.id}'), dictionary: selected),
            ],
          );
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTabIndex,
        onDestinationSelected: (index) => setState(() => _selectedTabIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Главная'),
          NavigationDestination(icon: Icon(Icons.auto_stories_outlined), label: 'Уроки'),
          NavigationDestination(icon: Icon(Icons.fitness_center_outlined), label: 'Практика'),
        ],
      ),
    );
  }
}
