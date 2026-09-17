import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/dictionary.dart';
import 'login_screen.dart';
import 'main_menu_screen.dart';

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
/// Bottom nav is deliberately just one "Главная" destination for now --
/// a temporary structure (see MainMenuScreen) while every feature still
/// lives behind a single entry point rather than its own tab.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late Future<List<GuyoDictionary>> _dictionariesFuture;
  GuyoDictionary? _selectedDictionary;

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

          // Keying by dictionary id makes the menu (and whatever feature
          // gets pushed from it) rebuild fresh whenever the selected
          // language changes.
          return MainMenuScreen(key: ValueKey('menu-${selected.id}'), dictionary: selected);
        },
      ),
      // Flutter's NavigationBar/BottomNavigationBar both require at least
      // two destinations (an assertion, not a style choice) -- with only
      // one "Главная" entry for this temporary structure, a plain custom
      // bar is simpler than working around that restriction.
      bottomNavigationBar: _SingleDestinationBottomBar(
        icon: Icons.home_outlined,
        label: 'Главная',
      ),
    );
  }
}

/// A minimal stand-in for [NavigationBar] with exactly one, always-selected
/// destination -- kept only because the real NavigationBar widget refuses
/// to render with fewer than two. Visually matches it closely enough
/// (surface background, primary-colored icon+label) without pulling in any
/// navigation behavior of its own; there's nothing to switch to yet.
class _SingleDestinationBottomBar extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SingleDestinationBottomBar({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
