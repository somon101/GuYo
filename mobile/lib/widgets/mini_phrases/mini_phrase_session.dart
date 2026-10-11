import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../models/mini_phrase.dart';
import '../../theme/app_colors.dart';
import 'mini_phrase_build.dart';
import 'mini_phrase_explanation.dart';

/// Goes through [phrases] one by one: the explanation, then "Собери
/// фразу". Used at the end of a lesson (after the word exercises, before
/// the results) and in Практика. Calls [onDone] after the last one.
class MiniPhraseSession extends StatefulWidget {
  final List<MiniPhrase> phrases;
  final int? lessonId;
  final VoidCallback onDone;

  /// Практика skips straight to the exercise when the learner asked to
  /// practise; a lesson always explains first.
  final bool explainFirst;

  const MiniPhraseSession({
    super.key,
    required this.phrases,
    this.lessonId,
    required this.onDone,
    this.explainFirst = true,
  });

  @override
  State<MiniPhraseSession> createState() => _MiniPhraseSessionState();
}

class _MiniPhraseSessionState extends State<MiniPhraseSession> {
  int _index = 0;
  late bool _explaining = widget.explainFirst;

  void _next() {
    if (_index + 1 >= widget.phrases.length) {
      widget.onDone();
      return;
    }
    setState(() {
      _index++;
      _explaining = widget.explainFirst;
    });
  }

  @override
  Widget build(BuildContext context) {
    final phrase = widget.phrases[_index];
    final total = widget.phrases.length;
    return Column(
      children: [
        if (total > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                for (var i = 0; i < total; i++)
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      height: 5,
                      margin: EdgeInsets.only(right: i == total - 1 ? 0 : 6),
                      decoration: BoxDecoration(
                        color: i <= _index ? AppColors.primary : AppColors.progressTrack,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(a),
                child: child,
              ),
            ),
            child: _explaining
                ? MiniPhraseExplanation(
                    key: ValueKey('explain-${phrase.id}-$_index'),
                    phrase: phrase,
                    nextLabel: tr('Собрать фразу'),
                    onNext: () => setState(() => _explaining = false),
                  )
                : MiniPhraseBuildExercise(
                    key: ValueKey('build-${phrase.id}-$_index'),
                    phrase: phrase,
                    lessonId: widget.lessonId,
                    onDone: (_) => _next(),
                  ),
          ),
        ),
      ],
    );
  }
}
