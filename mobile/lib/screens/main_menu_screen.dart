import 'package:flutter/material.dart';
import '../models/dictionary.dart';
import 'dictionary_words_screen.dart';
import 'learning_screen.dart';
import 'matching_screen.dart';

/// Temporary central hub for every currently-available feature.
///
/// This is deliberately NOT where these features are meant to live
/// long-term -- once everything is built and tested, "Словарь"/"Изучение
/// слов"/"Сопоставление" may move to their own bottom-nav tabs, get
/// nested elsewhere, or be reorganized entirely. This screen owns none of
/// their logic; it's only a list of entry points, each pushing the
/// existing screen as-is (unwrapped, untouched) inside a plain Scaffold
/// so it gets a title and a back button.
///
/// A plain vertical list rather than a grid: for a handful of items this
/// needs far less height per row, so it never risks clipping an entry
/// below the fold on a short/landscape screen the way a multi-row grid of
/// square cards could.
class MainMenuScreen extends StatelessWidget {
  final GuyoDictionary dictionary;
  const MainMenuScreen({super.key, required this.dictionary});

  List<_MenuItem> get _items => [
        _MenuItem(
          icon: Icons.menu_book_outlined,
          label: 'Словарь',
          builder: (_) => DictionaryWordsScreen(dictionary: dictionary),
        ),
        _MenuItem(
          icon: Icons.school_outlined,
          label: 'Изучение слов',
          builder: (_) => LearningScreen(dictionary: dictionary),
        ),
        _MenuItem(
          icon: Icons.extension_outlined,
          label: 'Сопоставление',
          builder: (_) => MatchingScreen(dictionary: dictionary),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _MenuCard(item: items[index]),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String label;
  final WidgetBuilder builder;
  _MenuItem({required this.icon, required this.label, required this.builder});
}

class _MenuCard extends StatelessWidget {
  final _MenuItem item;
  const _MenuCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (innerContext) => Scaffold(
              appBar: AppBar(title: Text(item.label)),
              body: item.builder(innerContext),
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              Icon(item.icon, size: 28, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  item.label,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}
