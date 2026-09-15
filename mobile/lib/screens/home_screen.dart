import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/dictionary.dart';
import 'dictionary_words_screen.dart';
import 'login_screen.dart';
import 'matching_screen.dart';

/// The app's main hub, reached right after login.
///
/// Replaces the old "Выйти" button in the top bar with a language switcher:
/// picking a language selects the matching Dictionary (by `Dictionary.
/// language`), and that selection drives every section below -- currently
/// "Словарь" (the existing word list) and "Сопоставление" (the new
/// matching drill). Logging out is still available, just tucked into the
/// overflow menu instead of sitting in the main bar.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<GuyoDictionary>> _dictionariesFuture;
  GuyoDictionary? _selectedDictionary;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _dictionariesFuture = ApiClient.instance.fetchDictionaries();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GuYo'),
        actions: [
          FutureBuilder<List<GuyoDictionary>>(
            future: _dictionariesFuture,
            builder: (context, snapshot) {
              final dictionaries = snapshot.data;
              if (dictionaries == null || dictionaries.isEmpty) {
                return const SizedBox.shrink();
              }
              final options = _languageOptions(dictionaries);
              _selectedDictionary ??= options.first;
              // If the previously selected language disappeared (e.g. data
              // changed), fall back to the first available one instead of
              // pointing at a dictionary that's no longer offered.
              if (!options.any((d) => d.language == _selectedDictionary!.language)) {
                _selectedDictionary = options.first;
              }
              final current = options.firstWhere(
                (d) => d.language == _selectedDictionary!.language,
                orElse: () => options.first,
              );
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
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Не удалось загрузить словари', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _reloadDictionaries, child: const Text('Повторить')),
                  ],
                ),
              ),
            );
          }
          final dictionaries = snapshot.data ?? [];
          if (dictionaries.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Словарей пока нет', textAlign: TextAlign.center),
              ),
            );
          }
          final options = _languageOptions(dictionaries);
          _selectedDictionary ??= options.first;
          final selected = options.firstWhere(
            (d) => d.language == _selectedDictionary!.language,
            orElse: () => options.first,
          );

          return IndexedStack(
            index: _tabIndex,
            children: [
              // Keying by dictionary id makes each tab remount (and refetch
              // its own words from scratch) whenever the selected language
              // changes, without needing to touch that screen's internals.
              DictionaryWordsScreen(key: ValueKey('words-${selected.id}'), dictionary: selected),
              MatchingScreen(key: ValueKey('matching-${selected.id}'), dictionary: selected),
            ],
          );
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), label: 'Словарь'),
          NavigationDestination(icon: Icon(Icons.extension_outlined), label: 'Сопоставление'),
        ],
      ),
    );
  }
}
