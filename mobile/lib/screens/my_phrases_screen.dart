import '../l10n/l10n.dart';
import '../widgets/guyo_ui.dart';
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/dictionary.dart';
import '../models/phrase.dart';
import '../theme/app_colors.dart';
import '../widgets/audio_button.dart';
import '../widgets/skeleton.dart';

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
      appBar: AppBar(title: Text(tr('Мои фразы'))),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<GuyoPhrase>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SkeletonList(avatar: false);
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(tr('Не удалось загрузить фразы'), textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _reload, child: Text(tr('Повторить'))),
                      ],
                    ),
                  ),
                ],
              );
            }
            final phrases = snapshot.data ?? [];
            if (phrases.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 70),
                  GuyoEmptyState(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: tr('Пока нет доступных фраз'),
                    message: tr('Фраза появится здесь, как только вы изучите все слова в ней.'),
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

/// A phrase is shown collapsed (just the original + a chevron); tapping it
/// reveals the translation, transcription and audio. That tap is what
/// "opening a phrase" means -- reported once to the server (openPhrase) so
/// the "phrases_opened" achievement rewards a real action, not a phrase
/// merely becoming available.
class _PhraseTile extends StatefulWidget {
  final GuyoPhrase phrase;
  const _PhraseTile({required this.phrase});

  @override
  State<_PhraseTile> createState() => _PhraseTileState();
}

class _PhraseTileState extends State<_PhraseTile> {
  bool _expanded = false;
  bool _reported = false;

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded && !_reported) {
      _reported = true;
      // Fire-and-forget: counts once per phrase on the server anyway.
      ApiClient.instance.openPhrase(widget.phrase.dictionaryId, widget.phrase.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phrase = widget.phrase;
    final hasTranscription = phrase.transcription != null && phrase.transcription!.isNotEmpty;
    final hasOriginalAudio = phrase.originalAudioUrl != null && phrase.originalAudioUrl!.isNotEmpty;
    final hasTranslationAudio = phrase.translationAudioUrl != null && phrase.translationAudioUrl!.isNotEmpty;

    return InkWell(
      onTap: _toggle,
      child: Padding(
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
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Icons.expand_more_rounded, color: AppColors.secondaryText),
                ),
              ],
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 180),
              crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasTranscription)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        phrase.transcription!,
                        style: TextStyle(fontSize: 13, color: AppColors.secondaryText),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(phrase.shownTranslation, style: const TextStyle(fontSize: 15)),
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
            ),
          ],
        ),
      ),
    );
  }
}
