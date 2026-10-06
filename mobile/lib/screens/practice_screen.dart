import '../l10n/l10n.dart';
import 'package:flutter/material.dart';
import '../exercises/practice_catalog.dart';
import '../models/dictionary.dart';
import '../theme/app_colors.dart';
import '../widgets/exercise_tile.dart';

/// "Практика": self-directed training outside the Уроки sequence, entirely
/// independent of lesson order/completion. Every exercise shown here draws
/// its words/phrases from "Мои слова" (already-learned words) -- never
/// from words the user hasn't learned yet -- via the same backend data
/// "Мои слова"/"Мои фразы" already use.
///
/// The screen itself knows nothing about which exercises exist: it renders
/// whatever exercises/practice_catalog.dart lists, as a grid of the shared
/// [ExerciseTile]. Adding a practice type is one entry in that catalog,
/// with nothing to change here.
class PracticeScreen extends StatelessWidget {
  final GuyoDictionary dictionary;
  const PracticeScreen({super.key, required this.dictionary});

  @override
  Widget build(BuildContext context) {
    final exercises = practiceExercises(dictionary);

    return Container(
      color: AppColors.canvas,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Text(
              tr('Практика'),
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
            ),
            const SizedBox(height: 2),
            Text(
              tr('Тренируйтесь самостоятельно, вне уроков'),
              style: TextStyle(fontSize: 13, color: AppColors.secondaryText),
            ),
            const SizedBox(height: 18),
            if (exercises.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  tr('Упражнений пока нет'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.secondaryText),
                ),
              )
            else
              ExerciseGrid(
                tiles: [
                  for (final exercise in exercises)
                    ExerciseTile(
                      icon: exercise.type.icon,
                      title: exercise.type.label,
                      description: exercise.description,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: exercise.builder),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
