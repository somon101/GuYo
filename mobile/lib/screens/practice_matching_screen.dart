import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/dictionary.dart';
import '../models/word.dart';
import '../theme/app_colors.dart';
import '../widgets/exercises/matching_board.dart';
import '../widgets/exercises/practice_round_complete.dart';

/// «Практика» for «Сопоставление»: renders the EXACT SAME [MatchingBoard]
/// widget Уроки uses, fed a fresh random board of "Мои изученные слова"
/// (see backend/app/routers/practice.py's /practice/matching). Its own
/// host, separate from [PracticeExerciseScreen], because a board is not a
/// sequence of single items the way the other 4 types are -- there is
/// nothing to step through, only one board per round.
///
/// Never reports a match anywhere: Practice keeps no score of its own.
class PracticeMatchingScreen extends StatefulWidget {
  final GuyoDictionary dictionary;
  const PracticeMatchingScreen({super.key, required this.dictionary});

  @override
  State<PracticeMatchingScreen> createState() => _PracticeMatchingScreenState();
}

class _PracticeMatchingScreenState extends State<PracticeMatchingScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<GuyoWord>? _words;
  bool _isComplete = false;
  // Bumped on every _load() so the board below always gets a fresh Key --
  // "Играть ещё раз" must start a genuinely new board even on the rare
  // chance the backend happens to sample the exact same words again.
  int _roundToken = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isComplete = false;
      _roundToken++;
    });
    try {
      final words = await ApiClient.instance.fetchPracticeMatchingWords(widget.dictionary.id);
      if (!mounted) return;
      setState(() {
        _words = words;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Не удалось загрузить упражнение';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Сопоставление')),
      body: SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: _buildBody())),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Повторить')),
          ],
        ),
      );
    }
    final words = _words;
    // A board needs at least 2 pairs to be a real matching task.
    if (words == null || words.length < 2) {
      return const PracticeEmptyState();
    }
    return Column(
      children: [
        Expanded(
          child: MatchingBoard(
            key: ValueKey(_roundToken),
            words: words,
            onComplete: () => setState(() => _isComplete = true),
          ),
        ),
        if (_isComplete) ...[
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Назад')),
              const SizedBox(width: 12),
              FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('Играть ещё раз')),
            ],
          ),
        ],
      ],
    );
  }
}
