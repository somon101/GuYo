import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/dictionary.dart';
import '../models/word.dart';
import '../widgets/audio_button.dart';

class DictionaryWordsScreen extends StatefulWidget {
  final GuyoDictionary dictionary;
  const DictionaryWordsScreen({super.key, required this.dictionary});

  @override
  State<DictionaryWordsScreen> createState() => _DictionaryWordsScreenState();
}

class _DictionaryWordsScreenState extends State<DictionaryWordsScreen> {
  late Future<List<GuyoWord>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiClient.instance.fetchWords(widget.dictionary.id);
  }

  Future<void> _reload() async {
    setState(() {
      _future = ApiClient.instance.fetchWords(widget.dictionary.id);
    });
    await _future;
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
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: words.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) => _WordTile(word: words[index]),
          );
        },
      ),
    );
  }
}

class _WordTile extends StatelessWidget {
  final GuyoWord word;
  const _WordTile({required this.word});

  @override
  Widget build(BuildContext context) {
    // Every optional field (transcription, image, word/translation audio)
    // is rendered only when present -- their absence is a normal state,
    // never an error or an empty placeholder.
    final hasImage = word.imageUrl != null && word.imageUrl!.isNotEmpty;
    final hasTranscription = word.transcription != null && word.transcription!.isNotEmpty;
    final hasWordAudio = word.wordAudioUrl != null && word.wordAudioUrl!.isNotEmpty;
    final hasTranslationAudio =
        word.translationAudioUrl != null && word.translationAudioUrl!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasImage) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                ApiClient.instance.mediaUrl(word.imageUrl!),
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(width: 56, height: 56),
              ),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      word.word,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    if (hasWordAudio) ...[
                      const SizedBox(width: 6),
                      AudioButton(url: ApiClient.instance.mediaUrl(word.wordAudioUrl!)),
                    ],
                  ],
                ),
                if (hasTranscription)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      word.transcription!,
                      style: const TextStyle(fontSize: 14, color: Colors.black45),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Text(word.translation, style: const TextStyle(fontSize: 16)),
                      if (hasTranslationAudio) ...[
                        const SizedBox(width: 6),
                        AudioButton(url: ApiClient.instance.mediaUrl(word.translationAudioUrl!)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
