import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/dictionary.dart';
import '../models/phrase.dart';
import '../widgets/audio_button.dart';

/// "Мои фразы": every Phrase whose every word the user has already
/// learned (directly, or via one of that word's own grammatical forms) --
/// entirely decided by the backend (see ApiClient.fetchAvailablePhrases),
/// this screen only renders whatever list it returns.
///
/// Deliberately NOT an exercise: no score, no progress, no repetition, no
/// per-phrase state at all -- just a live, read-only view that grows on
/// its own as the user learns more words. Reuses the existing Phrase data
/// as-is (original, transcription, translation, both audio files); no
/// separate storage of its own.
class MyPhrasesScreen extends StatefulWidget {
  final GuyoDictionary dictionary;
  const MyPhrasesScreen({super.key, required this.dictionary});

  @override
  State<MyPhrasesScreen> createState() => _MyPhrasesScreenState();
}

class _MyPhrasesScreenState extends State<MyPhrasesScreen> {
  late Future<List<GuyoPhrase>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiClient.instance.fetchAvailablePhrases(widget.dictionary.id);
  }

  Future<void> _reload() async {
    setState(() {
      _future = ApiClient.instance.fetchAvailablePhrases(widget.dictionary.id);
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Мои фразы')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<GuyoPhrase>>(
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
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Не удалось загрузить фразы', textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _reload, child: const Text('Повторить')),
                      ],
                    ),
                  ),
                ],
              );
            }
            final phrases = snapshot.data ?? [];
            if (phrases.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Пока нет доступных фраз.\nФраза появится здесь, как только вы изучите все слова в ней.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: phrases.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) => _PhraseTile(phrase: phrases[index]),
            );
          },
        ),
      ),
    );
  }
}

class _PhraseTile extends StatelessWidget {
  final GuyoPhrase phrase;
  const _PhraseTile({required this.phrase});

  @override
  Widget build(BuildContext context) {
    final hasTranscription = phrase.transcription != null && phrase.transcription!.isNotEmpty;
    final hasOriginalAudio = phrase.originalAudioUrl != null && phrase.originalAudioUrl!.isNotEmpty;
    final hasTranslationAudio = phrase.translationAudioUrl != null && phrase.translationAudioUrl!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  phrase.original,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
              if (hasOriginalAudio) ...[
                const SizedBox(width: 6),
                AudioButton(url: ApiClient.instance.mediaUrl(phrase.originalAudioUrl!)),
              ],
            ],
          ),
          if (hasTranscription)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(phrase.transcription!, style: const TextStyle(fontSize: 13, color: Colors.black45)),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(phrase.translationTg, style: const TextStyle(fontSize: 15)),
                ),
                if (hasTranslationAudio) ...[
                  const SizedBox(width: 6),
                  AudioButton(url: ApiClient.instance.mediaUrl(phrase.translationAudioUrl!)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
