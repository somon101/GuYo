import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../exercises/exercise_type.dart';
import '../l10n/l10n.dart';
import '../models/dictionary.dart';
import '../screens/practice_exercise_screen.dart';
import '../theme/app_colors.dart';

/// "Повторить сегодня" on Главная: learned words the memory model says are
/// being forgotten right now (GET .../practice/review-due). Tapping runs a
/// Собери слово round on exactly those words. Hidden when nothing is due,
/// or when it can't load -- it never blocks the rest of the screen.
class ReviewDueCard extends StatefulWidget {
  final GuyoDictionary dictionary;
  const ReviewDueCard({super.key, required this.dictionary});

  @override
  State<ReviewDueCard> createState() => ReviewDueCardState();
}

class ReviewDueCardState extends State<ReviewDueCard> {
  int _count = 0;
  List<int> _wordIds = const [];

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final due = await ApiClient.instance.fetchReviewDue(widget.dictionary.id);
      if (mounted) {
        setState(() {
          _count = due.$1;
          _wordIds = due.$2;
        });
      }
    } catch (_) {
      // Best effort only.
    }
  }

  Future<void> _open() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PracticeExerciseScreen(dictionary: widget.dictionary, type: buildWordExerciseType, wordIds: _wordIds),
      ),
    );
    reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('review-due-card'),
          borderRadius: BorderRadius.circular(20),
          onTap: _open,
          child: Ink(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF13B5A6), Color(0xFF1E90D6)],
              ),
              boxShadow: [BoxShadow(color: const Color(0xFF13B5A6).withValues(alpha: 0.28), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                  child: const Icon(Icons.psychology_rounded, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('Повторить сегодня'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tr('{0} слов начинают забываться', [_count]),
                        style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.88)),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: Text(
                    tr('Начать'),
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
