import 'dart:ui';

import 'package:flutter/material.dart';
import '../exercises/exercise_type.dart';
import '../models/dictionary.dart';
import 'build_phrase_by_ear_screen.dart';
import 'build_phrase_screen.dart';

/// One practice exercise type's entry in the "Практика" list -- adding a
/// future exercise (e.g. a word-based drill) is just one more entry here,
/// nothing about this screen or its layout is tied to "Собери фразу"
/// specifically.
class _PracticeExerciseDef {
  final String title;
  final String description;
  final IconData icon;
  final WidgetBuilder builder;

  const _PracticeExerciseDef({
    required this.title,
    required this.description,
    required this.icon,
    required this.builder,
  });
}

/// "Практика": self-directed training outside the Уроки sequence, entirely
/// independent of lesson order/completion. Every exercise listed here
/// draws its words/phrases from "Мои слова" (already-learned words) --
/// never from words the user hasn't learned yet -- via the same backend
/// data "Мои слова"/"Мои фразы" already use.
class PracticeScreen extends StatelessWidget {
  final GuyoDictionary dictionary;
  const PracticeScreen({super.key, required this.dictionary});

  List<_PracticeExerciseDef> get _exercises => [
        _PracticeExerciseDef(
          title: buildPhraseExerciseType.label,
          description: 'Восстановите пропущенное слово по переводу',
          icon: buildPhraseExerciseType.icon,
          builder: (_) => BuildPhraseScreen(dictionary: dictionary),
        ),
        _PracticeExerciseDef(
          title: buildPhraseByEarExerciseType.label,
          description: 'Прослушайте фразу и соберите её из слов',
          icon: buildPhraseByEarExerciseType.icon,
          builder: (_) => BuildPhraseByEarScreen(dictionary: dictionary),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.indigo.shade50, Colors.white],
              ),
            ),
          ),
        ),
        SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            children: [
              Text(
                'Практика',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.indigo.shade700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Тренируйтесь самостоятельно, вне уроков',
                style: TextStyle(color: Colors.black54, fontSize: 13),
              ),
              const SizedBox(height: 20),
              for (final exercise in _exercises) ...[
                _PracticeCard(exercise: exercise),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PracticeCard extends StatelessWidget {
  final _PracticeExerciseDef exercise;
  const _PracticeCard({required this.exercise});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Material(
          color: Colors.white.withValues(alpha: 0.7),
          child: InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: exercise.builder)),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.2),
                boxShadow: [
                  BoxShadow(color: Colors.indigo.withValues(alpha: 0.08), blurRadius: 18, offset: const Offset(0, 8)),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Colors.indigo.shade400, Colors.indigo.shade700],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Icon(exercise.icon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(exercise.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          exercise.description,
                          style: const TextStyle(fontSize: 13, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.black38),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
