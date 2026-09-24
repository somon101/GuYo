import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/dictionary.dart';
import '../models/word.dart';
import '../widgets/word_card.dart';
import 'word_detail_screen.dart';

class DictionaryWordsScreen extends StatefulWidget {
  final GuyoDictionary dictionary;
  const DictionaryWordsScreen({super.key, required this.dictionary});

  @override
  State<DictionaryWordsScreen> createState() => _DictionaryWordsScreenState();
}

class _DictionaryWordsScreenState extends State<DictionaryWordsScreen> {
  late Future<List<GuyoWord>> _future;
  // The level ladder only decides each card's color; a failure to load it
  // leaves the cards uncolored rather than failing the whole list.
  List<WordLevelSummary> _levels = [];

  @override
  void initState() {
    super.initState();
    _future = ApiClient.instance.fetchWords(widget.dictionary.id);
    _loadLevels();
  }

  Future<void> _loadLevels() async {
    try {
      final levels = await ApiClient.instance.fetchWordLevels();
      if (!mounted) return;
      setState(() => _levels = levels);
    } catch (_) {
      // Colorless cards are an acceptable degraded state.
    }
  }

  Future<void> _reload() async {
    setState(() {
      _future = ApiClient.instance.fetchWords(widget.dictionary.id);
    });
    await _future;
    await _loadLevels();
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
    // No Scaffold/AppBar here on purpose: this widget is now embedded as
    // the "Словарь" tab's content inside HomeScreen, which owns the
    // surrounding Scaffold (app bar + language switcher + bottom nav).
    return RefreshIndicator(
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
                  child: Text(
                    'Не удалось загрузить слова.\n${snapshot.error}',
                    textAlign: TextAlign.center,
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
                  child: Text('В этом словаре пока нет слов', textAlign: TextAlign.center),
                ),
              ],
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            itemCount: words.length,
            itemBuilder: (context, index) {
              final word = words[index];
              return WordCard(
                word: word.word,
                transcription: word.transcription,
                translation: word.translation,
                audioUrl: word.wordAudioUrl,
                level: WordLevelView.resolve(word.wordLevelId, word.wordLevelName, _levels),
                onTap: () => _openWord(word),
                trailing: const Icon(Icons.chevron_right, size: 18, color: Color(0xFFB9BEDA)),
              );
            },
          );
        },
      ),
    );
  }
}
