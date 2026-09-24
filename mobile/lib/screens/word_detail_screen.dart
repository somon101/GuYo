import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../theme/app_colors.dart';
import '../widgets/audio_button.dart';
import '../widgets/word_card.dart';

/// One word's own card, opened from any word list's chevron. Deliberately
/// compact: the word with its pronunciation and recording, the translation
/// with its own recording, the picture if the admin uploaded one, and the
/// current reinforcement level with its points. Everything here is already
/// in hand from the list that opened it -- this screen fetches nothing and
/// decides nothing, least of all which level a score belongs to.
class WordDetailScreen extends StatelessWidget {
  final String word;
  final String? transcription;
  final String? translation;
  final String? wordAudioUrl;
  final String? translationAudioUrl;
  final String? imageUrl;
  final int? score;
  final WordLevelView level;

  const WordDetailScreen({
    super.key,
    required this.word,
    required this.transcription,
    required this.translation,
    required this.wordAudioUrl,
    required this.translationAudioUrl,
    required this.imageUrl,
    required this.score,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Слово')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFEDEFF7)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 12, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasImage) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: CachedNetworkImage(
                        imageUrl: ApiClient.instance.mediaUrl(imageUrl!),
                        height: 150,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          word,
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                        ),
                      ),
                      if (wordAudioUrl != null && wordAudioUrl!.isNotEmpty)
                        AudioButton(url: ApiClient.instance.mediaUrl(wordAudioUrl!), size: 24),
                    ],
                  ),
                  if (transcription != null && transcription!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        transcription!,
                        style: const TextStyle(fontSize: 15, color: AppColors.secondaryText),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Container(height: 1, color: const Color(0xFFEDEFF7)),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          translation ?? '—',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.primaryDark),
                        ),
                      ),
                      if (translationAudioUrl != null && translationAudioUrl!.isNotEmpty)
                        AudioButton(url: ApiClient.instance.mediaUrl(translationAudioUrl!), size: 22),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: level.color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: level.color.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: level.color, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      level.name ?? 'Уровень не определён',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: level.color),
                    ),
                  ),
                  if (score != null)
                    Text(
                      '$score / 100',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.secondaryText),
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
