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
    _future = ApiClient.instance.fetchLearnedCategories(widget.dictionary.id);
  }

  Future<void> _reload() async {
    setState(() {
      _future = ApiClient.instance.fetchLearnedCategories(widget.dictionary.id);
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
  late Future<List<GuyoWord>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<GuyoWord>> _load() {
    final categoryId = widget.category.categoryId;
    return ApiClient.instance.fetchLearnedWords(
      widget.dictionary.id,
      categoryId: categoryId,
      uncategorized: categoryId == null,
    );
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
        child: FutureBuilder<List<GuyoWord>>(
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
            final words = snapshot.data ?? [];
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
              itemBuilder: (context, index) => _LearnedWordTile(word: words[index]),
            );
          },
        ),
      ),
    );
  }
}

class _LearnedWordTile extends StatelessWidget {
  final GuyoWord word;
  const _LearnedWordTile({required this.word});

  @override
  Widget build(BuildContext context) {
    final hasTranscription = word.transcription != null && word.transcription!.isNotEmpty;
    final hasWordAudio = word.wordAudioUrl != null && word.wordAudioUrl!.isNotEmpty;
    final hasTranslationAudio = word.translationAudioUrl != null && word.translationAudioUrl!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(word.word, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              if (hasWordAudio) ...[
                const SizedBox(width: 6),
                AudioButton(url: ApiClient.instance.mediaUrl(word.wordAudioUrl!)),
              ],
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
