import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/word_check.dart';
import '../theme/app_colors.dart';
import 'audio_button.dart';
import 'exercises/choice_tile.dart';
import 'guyo_ui.dart';
import 'remote_image.dart';

/// «Проверка слов» before a lesson's first pass: a card per word -- the
/// original on top, four translations below. After a right answer the learner
/// says how easy it was (угадал / трудно / нормально / легко); that, not the
/// tap itself, is what tells the memory model how well the word is known. The
/// answer is shown at once; a wrong answer asks nothing more. Calls [onDone]
/// after the last card or when skipped.
class WordCheckSession extends StatefulWidget {
  final int lessonId;
  final WordCheck check;
  final VoidCallback onDone;

  const WordCheckSession({
    super.key,
    required this.lessonId,
    required this.check,
    required this.onDone,
  });

  @override
  State<WordCheckSession> createState() => _WordCheckSessionState();
}

class _WordCheckSessionState extends State<WordCheckSession> {
  int _index = 0;
  int? _picked;
  bool? _correct;
  final _shownAt = Stopwatch()..start();

  CheckItem get _item => widget.check.items[_index];

  Future<void> _finish() async {
    await ApiClient.instance.finishWordCheck(widget.lessonId);
    if (mounted) widget.onDone();
  }

  void _next() {
    if (_index + 1 >= widget.check.items.length) {
      _finish();
      return;
    }
    setState(() {
      _index++;
      _picked = null;
      _correct = null;
      _shownAt
        ..reset()
        ..start();
    });
  }

  Future<void> _choose(CheckOption option) async {
    if (_picked != null) return;
    final item = _item;
    final correct = option.wordId == item.wordId;
    setState(() {
      _picked = option.wordId;
      _correct = correct;
    });
    if (!correct) {
      // A miss asks nothing more: it is recorded, then the next card.
      await ApiClient.instance.answerWordCheck(
        widget.lessonId,
        wordId: item.wordId,
        pickedWordId: option.wordId,
        durationMs: _shownAt.elapsedMilliseconds,
      );
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      if (mounted) _next();
    }
  }

  Future<void> _rate(CheckRating rating) async {
    final item = _item;
    await ApiClient.instance.answerWordCheck(
      widget.lessonId,
      wordId: item.wordId,
      pickedWordId: item.wordId,
      rating: rating,
      durationMs: _shownAt.elapsedMilliseconds,
    );
    if (mounted) _next();
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final total = widget.check.items.length;
    final ratingStage = _correct == true;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr('Проверка слов · {0} из {1}', [_index + 1, total]),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.secondaryText,
                  ),
                ),
              ),
              if (widget.check.skipAllowed)
                TextButton(
                  onPressed: _picked == null ? _finish : null,
                  child: Text(tr('Пропустить')),
                ),
            ],
          ),
          const SizedBox(height: 8),
          GuyoCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                if (item.imageUrl != null && item.imageUrl!.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppShapes.rowRadius),
                    child: RemoteImage(
                      url: item.imageUrl!,
                      width: 320,
                      height: 140,
                      fit: BoxFit.cover,
                      fallbackBuilder: () => const SizedBox(height: 0),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        item.original,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ),
                    if (item.wordAudioUrl != null &&
                        item.wordAudioUrl!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      AudioButton(
                        url: ApiClient.instance.mediaUrl(item.wordAudioUrl!),
                        size: 22,
                      ),
                    ],
                  ],
                ),
                if (item.transcription != null &&
                    item.transcription!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      item.transcription!,
                      style: TextStyle(
                        fontSize: 15,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final option in item.options) ...[
            ChoiceTile(
              label: option.text,
              isSelected: _picked == option.wordId,
              isRevealed: _picked != null,
              isCorrectOption: option.wordId == item.wordId,
              onTap: _picked == null ? () => _choose(option) : null,
            ),
            const SizedBox(height: 10),
          ],
          if (ratingStage) ...[
            const SizedBox(height: 8),
            Text(
              tr('Насколько это было легко?'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.primaryDark,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final r in CheckRating.values) ...[
                  if (r != CheckRating.values.first) const SizedBox(width: 6),
                  Expanded(
                    child: _RatingButton(
                      label: _ratingLabel(r),
                      rating: r,
                      onTap: _rate,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String _ratingLabel(CheckRating r) => switch (r) {
  CheckRating.guess => tr('Угадал'),
  CheckRating.hard => tr('Трудно'),
  CheckRating.normal => tr('Нормально'),
  CheckRating.easy => tr('Легко'),
};

class _RatingButton extends StatelessWidget {
  final String label;
  final CheckRating rating;
  final void Function(CheckRating) onTap;

  const _RatingButton({
    required this.label,
    required this.rating,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      key: ValueKey('check-rating-${rating.name}'),
      onPressed: () => onTap(rating),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 12),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label, style: const TextStyle(fontSize: 13.5)),
      ),
    );
  }
}
