import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/word.dart';
import '../theme/app_colors.dart';
import 'audio_button.dart';

/// Position-based red-to-green color for a word level: the backend decides
/// WHICH level a word is in and the levels' own order (ordered_enabled_levels
/// there, mirrored 1:1 by GET /word-levels) -- this is the one purely
/// visual mapping left to the client, from that position alone. Shared so
/// every list and every screen tints the same level identically.
Color wordLevelColor(int index, int total) {
  if (index < 0 || total <= 0) return AppColors.secondaryText;
  if (total == 1) return AppColors.success;
  final t = index / (total - 1);
  // Red -> brown/orange -> amber -> light green -> green, matching the
  // "новое / слабое / среднее / хорошо / закреплено" progression.
  const stops = [
    Color(0xFFEF4056), // новое
    Color(0xFFB4713C), // слабое
    Color(0xFFF2B233), // среднее
    Color(0xFF4CC38A), // хорошо
    Color(0xFF14A45C), // закреплено
  ];
  final scaled = t * (stops.length - 1);
  final lower = scaled.floor().clamp(0, stops.length - 1);
  final upper = scaled.ceil().clamp(0, stops.length - 1);
  return Color.lerp(stops[lower], stops[upper], scaled - lower)!;
}

/// Everything the shared word card needs to know about one word's current
/// level, resolved once by the caller from the level ladder it already
/// loaded (see WordLevelSummary) rather than re-derived per card.
class WordLevelView {
  final String? name;
  final Color color;
  const WordLevelView({required this.name, required this.color});

  /// Looks [levelId] up in [levels] (the backend's own ordered ladder) and
  /// picks that position's color. Falls back to a neutral, nameless state
  /// when the word has no level yet or the ladder isn't loaded.
  factory WordLevelView.resolve(int? levelId, String? levelName, List<WordLevelSummary> levels) {
    final index = levelId == null ? -1 : levels.indexWhere((l) => l.id == levelId);
    return WordLevelView(name: levelName, color: wordLevelColor(index, levels.length));
  }
}

/// The app's ONE word row, used by every list that shows words (Мои слова,
/// Словарь, a lesson's own word list, the lesson word picker): a colored
/// level stripe down the left edge, the word with its pronunciation, a play
/// button for its recording, the translation, and the level pill.
///
/// [trailing] is what sits at the far right -- a chevron for a row that
/// opens the word, or a checkbox in a picker. [footer] is an optional
/// extra line under that row (the lesson results screen puts its
/// per-word progress bar there). [onTap] is optional so a read-only list
/// can use the exact same card.
class WordCard extends StatelessWidget {
  final String word;
  final String? transcription;
  final String? translation;
  final String? audioUrl;
  final WordLevelView level;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Widget? footer;
  final bool selected;

  const WordCard({
    super.key,
    required this.word,
    required this.transcription,
    required this.translation,
    required this.audioUrl,
    required this.level,
    this.onTap,
    this.trailing,
    this.footer,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasAudio = audioUrl != null && audioUrl!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AppColors.primary.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? AppColors.primary.withValues(alpha: 0.35) : const Color(0xFFEDEFF7)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 3)),
              ],
            ),
            // The level stripe is the card's own left edge, so it reads as
            // part of the card rather than a separate bar next to it.
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    Container(width: 5, color: level.color),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  flex: 4,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        word,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.primaryDark,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (transcription != null && transcription!.isNotEmpty)
                                        Text(
                                          transcription!,
                                          style: const TextStyle(fontSize: 12, color: AppColors.secondaryText),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                SizedBox(
                                  width: 34,
                                  child: hasAudio
                                      ? Center(child: AudioButton(url: ApiClient.instance.mediaUrl(audioUrl!), size: 18))
                                      : const SizedBox.shrink(),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  flex: 4,
                                  child: Text(
                                    translation ?? '',
                                    style: const TextStyle(fontSize: 13, color: AppColors.secondaryText),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (level.name != null) ...[
                                  const SizedBox(width: 6),
                                  _LevelPill(level: level),
                                ],
                                if (trailing != null) ...[
                                  const SizedBox(width: 2),
                                  trailing!,
                                ],
                              ],
                            ),
                            if (footer != null) ...[
                              const SizedBox(height: 8),
                              footer!,
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LevelPill extends StatelessWidget {
  final WordLevelView level;
  const _LevelPill({required this.level});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: level.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: level.color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 96),
            child: Text(
              level.name!,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: level.color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
