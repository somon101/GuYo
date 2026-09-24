import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/dictionary.dart';
import '../models/learning.dart';
import '../models/word.dart';
import '../theme/app_colors.dart';
import '../widgets/remote_image.dart';
import '../widgets/word_card.dart';
import 'my_phrases_screen.dart';
import 'word_detail_screen.dart';

/// "Мои слова": every Word this user has any progress on in the current
/// language, grouped by the same Category the dictionary already uses.
///
/// One screen, not two: search, the category picker, the level filter and
/// the words themselves all live here, and a category is a collapsible
/// group rather than a separate screen to drill into. Everything the
/// filters do is local to the list the backend already returned -- the
/// score, the level and the category of each word are all decided server
/// side (GET /learned-words?include_in_progress=true), never here.
class LearnedWordsScreen extends StatefulWidget {
  final GuyoDictionary dictionary;
  const LearnedWordsScreen({super.key, required this.dictionary});

  @override
  State<LearnedWordsScreen> createState() => _LearnedWordsScreenState();
}

class _LearnedWordsScreenState extends State<LearnedWordsScreen> {
  bool _isLoading = true;
  String? _loadError;
  List<GuyoWord> _words = [];
  List<LearnedCategory> _categories = [];
  List<WordLevelSummary> _levels = [];

  final _searchController = TextEditingController();
  String _search = '';
  // null = "Все"; otherwise the selected level's own id.
  int? _levelFilterId;
  // Set only when the user picks one category in the dropdown; null shows
  // every category as its own group.
  int? _categoryFilterId;
  bool _categoryFilterIsUncategorized = false;
  // Categories the user has collapsed, by the same key the groups use.
  final Set<String> _collapsed = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        ApiClient.instance.fetchLearnedWords(widget.dictionary.id, includeInProgress: true),
        ApiClient.instance.fetchLearnedCategories(widget.dictionary.id, includeInProgress: true),
        ApiClient.instance.fetchWordLevels(),
      ]);
      if (!mounted) return;
      setState(() {
        _words = results[0] as List<GuyoWord>;
        _categories = results[1] as List<LearnedCategory>;
        _levels = results[2] as List<WordLevelSummary>;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Не удалось загрузить слова';
      });
    }
  }

  String _groupKey(int? categoryId) => categoryId?.toString() ?? 'none';

  /// Words left after the search box and the level chip -- the category
  /// filter is applied when the groups themselves are built, so a filtered
  /// category still shows its own header and count.
  List<GuyoWord> get _filteredWords {
    final query = _search.trim().toLowerCase();
    return _words.where((w) {
      if (_levelFilterId != null && w.wordLevelId != _levelFilterId) return false;
      if (query.isEmpty) return true;
      // Searches the original word AND its translation, so either side of
      // the pair finds the card.
      return w.word.toLowerCase().contains(query) || w.translation.toLowerCase().contains(query);
    }).toList();
  }

  void _openWord(GuyoWord word) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WordDetailScreen(
          word: word.word,
          transcription: word.transcription,
          translation: word.translation,
          wordAudioUrl: word.wordAudioUrl,
          translationAudioUrl: word.translationAudioUrl,
          imageUrl: word.imageUrl,
          score: word.score,
          level: WordLevelView.resolve(word.wordLevelId, word.wordLevelName, _levels),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Near-white with the faintest blue cast, so the white cards and the
      // light-violet accents both read against it.
      backgroundColor: const Color(0xFFFBFCFE),
      appBar: AppBar(title: const Text('Мои слова')),
      body: SafeArea(
        child: RefreshIndicator(onRefresh: _load, child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return ListView(children: const [SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))]);
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

    final filtered = _filteredWords;
    // Groups follow the category list the backend returned (so their order
    // and names match everywhere), narrowed to the picked category if any.
    final groups = _categories.where((c) {
      if (_categoryFilterId == null && !_categoryFilterIsUncategorized) return true;
      if (_categoryFilterIsUncategorized) return c.categoryId == null;
      return c.categoryId == _categoryFilterId;
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _SearchField(
          controller: _searchController,
          onChanged: (value) => setState(() => _search = value),
        ),
        const SizedBox(height: 10),
        _FilterRow(
          categories: _categories,
          levels: _levels,
          selectedCategoryId: _categoryFilterId,
          uncategorizedSelected: _categoryFilterIsUncategorized,
          selectedLevelId: _levelFilterId,
          onCategoryChanged: (categoryId, isUncategorized) => setState(() {
            _categoryFilterId = categoryId;
            _categoryFilterIsUncategorized = isUncategorized;
          }),
          onLevelChanged: (levelId) => setState(() => _levelFilterId = levelId),
        ),
        const SizedBox(height: 14),
        _PhrasesLink(dictionary: widget.dictionary),
        const SizedBox(height: 12),
        if (groups.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('Пока нет слов', textAlign: TextAlign.center, style: TextStyle(color: AppColors.secondaryText)),
          )
        else
          for (final category in groups) ...[
            Builder(
              builder: (context) {
                final key = _groupKey(category.categoryId);
                final words = filtered.where((w) => w.categoryId == category.categoryId).toList();
                final isCollapsed = _collapsed.contains(key);
                // A category with nothing left after the current search or
                // level filter is hidden entirely rather than shown empty.
                if (words.isEmpty && (_search.isNotEmpty || _levelFilterId != null)) {
                  return const SizedBox.shrink();
                }
                return Column(
                  children: [
                    _CategoryHeader(
                      category: category,
                      shownCount: words.length,
                      isCollapsed: isCollapsed,
                      onTap: () => setState(() {
                        if (isCollapsed) {
                          _collapsed.remove(key);
                        } else {
                          _collapsed.add(key);
                        }
                      }),
                    ),
                    if (!isCollapsed) ...[
                      const SizedBox(height: 8),
                      for (final word in words)
                        WordCard(
                          word: word.word,
                          transcription: word.transcription,
                          translation: word.translation,
                          audioUrl: word.wordAudioUrl,
                          level: WordLevelView.resolve(word.wordLevelId, word.wordLevelName, _levels),
                          onTap: () => _openWord(word),
                          trailing: const Icon(Icons.chevron_right, size: 18, color: Color(0xFFB9BEDA)),
                        ),
                    ],
                    const SizedBox(height: 12),
                  ],
                );
              },
            ),
          ],
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _SearchField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14, color: AppColors.primaryDark),
      decoration: InputDecoration(
        hintText: 'Поиск слов...',
        hintStyle: const TextStyle(fontSize: 14, color: AppColors.secondaryText),
        prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.secondaryText),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        filled: true,
        fillColor: const Color(0xFFF2F3FA),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
      ),
    );
  }
}

/// The category picker and the level chips on one scrollable line, so
/// neither ever pushes the word list down the screen.
class _FilterRow extends StatelessWidget {
  final List<LearnedCategory> categories;
  final List<WordLevelSummary> levels;
  final int? selectedCategoryId;
  final bool uncategorizedSelected;
  final int? selectedLevelId;
  final void Function(int? categoryId, bool isUncategorized) onCategoryChanged;
  final ValueChanged<int?> onLevelChanged;

  const _FilterRow({
    required this.categories,
    required this.levels,
    required this.selectedCategoryId,
    required this.uncategorizedSelected,
    required this.selectedLevelId,
    required this.onCategoryChanged,
    required this.onLevelChanged,
  });

  String _currentCategoryLabel() {
    if (uncategorizedSelected) return 'Без категории';
    if (selectedCategoryId == null) return 'Все категории';
    for (final c in categories) {
      if (c.categoryId == selectedCategoryId) return c.categoryName;
    }
    return 'Все категории';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          PopupMenuButton<String>(
            tooltip: 'Категория',
            onSelected: (value) {
              if (value == 'all') {
                onCategoryChanged(null, false);
              } else if (value == 'none') {
                onCategoryChanged(null, true);
              } else {
                onCategoryChanged(int.parse(value), false);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('Все категории')),
              for (final c in categories)
                PopupMenuItem(
                  value: c.categoryId?.toString() ?? 'none',
                  child: Text(c.categoryName),
                ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: const Color(0xFFE3E6F5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.folder_outlined, size: 16, color: AppColors.primary),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(
                      _currentCategoryLabel(),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primaryDark),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down, size: 18, color: AppColors.secondaryText),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _LevelChip(
            label: 'Все',
            color: AppColors.primary,
            selected: selectedLevelId == null,
            onTap: () => onLevelChanged(null),
          ),
          // One chip per level the admin actually configured, in the
          // backend's own order -- adding or removing a level in Admin Web
          // changes this row with no client change at all.
          for (var i = 0; i < levels.length; i++) ...[
            const SizedBox(width: 6),
            _LevelChip(
              label: _shortLevelLabel(levels[i], i),
              color: wordLevelColor(i, levels.length),
              selected: selectedLevelId == levels[i].id,
              onTap: () => onLevelChanged(levels[i].id),
            ),
          ],
        ],
      ),
    );
  }

  /// Levels are named like "3 — Среднее", so the chip shows just the
  /// leading number when there is one, and falls back to the position.
  String _shortLevelLabel(WordLevelSummary level, int index) {
    final match = RegExp(r'^\s*(\d+)').firstMatch(level.name);
    return match?.group(1) ?? '$index';
  }
}

class _LevelChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _LevelChip({required this.label, required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : Colors.white,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: selected ? AppColors.primary : const Color(0xFFE3E6F5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: selected ? Colors.white : color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.primaryDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  final LearnedCategory category;
  final int shownCount;
  final bool isCollapsed;
  final VoidCallback onTap;

  const _CategoryHeader({
    required this.category,
    required this.shownCount,
    required this.isCollapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconUrl = category.iconUrl;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFEDEFF7)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF0FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: iconUrl != null && iconUrl.isNotEmpty
                    ? RemoteImage(
                        url: iconUrl,
                        width: 40,
                        height: 40,
                        fit: BoxFit.contain,
                        fallbackBuilder: () =>
                            const Icon(Icons.folder_outlined, color: AppColors.primary, size: 20),
                      )
                    : const Icon(Icons.folder_outlined, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.categoryName,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '$shownCount ${_wordWord(shownCount)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.secondaryText),
                    ),
                  ],
                ),
              ),
              Icon(
                isCollapsed ? Icons.chevron_right : Icons.keyboard_arrow_down,
                color: const Color(0xFFB9BEDA),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _wordWord(int n) {
    final mod100 = n % 100;
    if (mod100 >= 11 && mod100 <= 14) return 'слов';
    switch (n % 10) {
      case 1:
        return 'слово';
      case 2:
      case 3:
      case 4:
        return 'слова';
      default:
        return 'слов';
    }
  }
}

/// "Мои фразы" is its own thing -- not an exercise, not tied to level or
/// lesson state -- so it sits beside the word list rather than inside it.
class _PhrasesLink extends StatelessWidget {
  final GuyoDictionary dictionary;
  const _PhrasesLink({required this.dictionary});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFEEF0FF),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => MyPhrasesScreen(dictionary: dictionary)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.chat_bubble_outline, size: 20, color: AppColors.primary),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Мои фразы',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}
