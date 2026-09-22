import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/dictionary.dart';
import '../models/learning.dart';
import '../models/word.dart';
import '../widgets/audio_button.dart';
import 'my_phrases_screen.dart';

/// "Мои изученные слова": every Word (by word_id, no copies) the user has
/// marked "Изучил" in the current language, grouped by the same Category
/// the dictionary already uses. Only categories with at least one learned
/// word show up -- this is a live count from the backend, not a fixed list,
/// so a brand new category appears the moment its first word is learned.
class LearnedWordsScreen extends StatefulWidget {
  final GuyoDictionary dictionary;
  const LearnedWordsScreen({super.key, required this.dictionary});

  @override
  State<LearnedWordsScreen> createState() => _LearnedWordsScreenState();
}

class _LearnedWordsScreenState extends State<LearnedWordsScreen> {
  late Future<List<LearnedCategory>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiClient.instance.fetchLearnedCategories(widget.dictionary.id, includeInProgress: true);
  }

  Future<void> _reload() async {
    setState(() {
      _future = ApiClient.instance.fetchLearnedCategories(widget.dictionary.id, includeInProgress: true);
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Мои изученные слова')),
      body: Column(
        children: [
          // A separate, always-present entry point -- not an exercise, not
          // tied to lesson/score state, so it belongs beside "Мои слова"
          // rather than nested inside its (learned-words-only) list below.
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('Мои фразы'),
              subtitle: const Text('Фразы, где изучены все слова'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => MyPhrasesScreen(dictionary: widget.dictionary)),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reload,
              child: FutureBuilder<List<LearnedCategory>>(
                future: _future,
                builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Text('Не удалось загрузить изученные слова', textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _reload, child: const Text('Повторить')),
                      ],
                    ),
                  ),
                ],
              );
            }
            final categories = snapshot.data ?? [];
            if (categories.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Вы ещё не изучили ни одного слова.\nНачните изучение слов, чтобы они появились здесь.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: categories.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final category = categories[index];
                return ListTile(
                  title: Text(category.categoryName),
                  trailing: Text(
                    '${category.learnedCount}',
                    style: const TextStyle(color: Colors.black54),
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _LearnedWordsInCategoryScreen(
                        dictionary: widget.dictionary,
                        category: category,
                      ),
                    ),
                  ),
                );
              },
            );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LearnedWordsInCategoryScreen extends StatefulWidget {
  final GuyoDictionary dictionary;
  final LearnedCategory category;
  const _LearnedWordsInCategoryScreen({required this.dictionary, required this.category});

  @override
  State<_LearnedWordsInCategoryScreen> createState() => _LearnedWordsInCategoryScreenState();
}

class _LearnedWordsInCategoryScreenState extends State<_LearnedWordsInCategoryScreen> {
  // Words and the level ladder load together: the ladder's own order is
  // what turns each word's word_level_id into a red-to-green badge
  // position (see _LearnedWordTile), so the tile list has nothing useful
  // to render until both are in.
  late Future<(List<GuyoWord>, List<WordLevelSummary>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(List<GuyoWord>, List<WordLevelSummary>)> _load() async {
    final categoryId = widget.category.categoryId;
    final results = await Future.wait([
      ApiClient.instance.fetchLearnedWords(
        widget.dictionary.id,
        categoryId: categoryId,
        uncategorized: categoryId == null,
        includeInProgress: true,
      ),
      ApiClient.instance.fetchWordLevels(),
    ]);
    return (results[0] as List<GuyoWord>, results[1] as List<WordLevelSummary>);
  }

  Future<void> _reload() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.category.categoryName)),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<(List<GuyoWord>, List<WordLevelSummary>)>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Text('Не удалось загрузить слова', textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _reload, child: const Text('Повторить')),
                      ],
                    ),
                  ),
                ],
              );
            }
            final (words, levels) = snapshot.data ?? (<GuyoWord>[], <WordLevelSummary>[]);
            if (words.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('В этой категории пока нет изученных слов', textAlign: TextAlign.center),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: words.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) => _LearnedWordTile(word: words[index], levels: levels),
            );
          },
        ),
      ),
    );
  }
}

/// Position-based red-to-green color for a word level: the backend decides
/// WHICH level a word is in and the levels' own order (ordered_enabled_levels
/// on the backend, mirrored 1:1 by GET /word-levels) -- this is the one
/// purely visual mapping left to the client, from that position alone.
Color _wordLevelColor(int index, int total) {
  if (total <= 1) return const Color(0xFF43A047);
  final t = index / (total - 1);
  return Color.lerp(const Color(0xFFE53935), const Color(0xFF43A047), t)!;
}

class _LearnedWordTile extends StatelessWidget {
  final GuyoWord word;
  final List<WordLevelSummary> levels;
  const _LearnedWordTile({required this.word, required this.levels});

  @override
  Widget build(BuildContext context) {
    final hasTranscription = word.transcription != null && word.transcription!.isNotEmpty;
    final hasWordAudio = word.wordAudioUrl != null && word.wordAudioUrl!.isNotEmpty;
    final hasTranslationAudio = word.translationAudioUrl != null && word.translationAudioUrl!.isNotEmpty;

    final levelIndex = word.wordLevelId == null ? -1 : levels.indexWhere((l) => l.id == word.wordLevelId);
    final levelColor = levelIndex == -1 ? null : _wordLevelColor(levelIndex, levels.length);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(word.word, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    if (hasWordAudio) ...[
                      const SizedBox(width: 6),
                      AudioButton(url: ApiClient.instance.mediaUrl(word.wordAudioUrl!)),
                    ],
                  ],
                ),
              ),
              if (levelColor != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: levelColor.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: levelColor.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: levelColor, shape: BoxShape.circle),
                      ),
                      if (word.wordLevelName != null) ...[
                        const SizedBox(width: 5),
                        Text(
                          word.wordLevelName!,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: levelColor),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
          if (hasTranscription)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(word.transcription!, style: const TextStyle(fontSize: 13, color: Colors.black45)),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Text(word.translation, style: const TextStyle(fontSize: 15)),
                if (hasTranslationAudio) ...[
                  const SizedBox(width: 6),
                  AudioButton(url: ApiClient.instance.mediaUrl(word.translationAudioUrl!)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
