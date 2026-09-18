import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/dictionary.dart';
import '../models/learning.dart';
import '../models/word.dart';
import '../widgets/audio_button.dart';
import 'learned_words_screen.dart';

/// Allowed range for "how many new words" -- enforced again on the backend,
/// this is just so the UI doesn't even offer an out-of-range value.
const int _minSessionCount = 3;
const int _maxSessionCount = 20;

/// "Изучение слов": a per-language queue of Word cards the user hasn't
/// learned yet. All state (the fixed word set, per-word progress, whether
/// the session is done) lives on the backend -- this screen only ever
/// reflects whatever the last response said, and reloads that on resume
/// rather than keeping its own notion of progress.
class LearningScreen extends StatefulWidget {
  final GuyoDictionary dictionary;
  const LearningScreen({super.key, required this.dictionary});

  @override
  State<LearningScreen> createState() => _LearningScreenState();
}

class _LearningScreenState extends State<LearningScreen> {
  bool _isLoading = true;
  String? _loadError;
  LearningSession? _session;
  bool _showCountPicker = false;
  bool _isCreating = false;
  String? _createError;
  bool _isActing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final session = await ApiClient.instance.fetchActiveLearningSession(widget.dictionary.id);
      if (!mounted) return;
      setState(() {
        _session = session;
        _isLoading = false;
        _showCountPicker = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Не удалось загрузить изучение слов';
      });
    }
  }

  Future<void> _createSession(int count) async {
    setState(() {
      _isCreating = true;
      _createError = null;
    });
    try {
      final session = await ApiClient.instance.createLearningSession(widget.dictionary.id, count);
      if (!mounted) return;
      setState(() {
        _session = session;
        _isCreating = false;
        _showCountPicker = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isCreating = false;
        _createError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isCreating = false;
        _createError = 'Не удалось создать сессию изучения';
      });
    }
  }

  Future<void> _markLearned(int wordId) async {
    if (_isActing || _session == null) return;
    setState(() => _isActing = true);
    try {
      final updated = await ApiClient.instance.markWordLearned(_session!.id, wordId);
      if (!mounted) return;
      setState(() {
        _session = updated;
        _isActing = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isActing = false);
      if (e.statusCode == 404) {
        // The session finished by some other path (e.g. another device) --
        // the backend is authoritative, so just resync instead of guessing.
        _load();
      } else {
        _showSnack(e.message);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isActing = false);
      _showSnack('Не удалось сохранить. Проверьте соединение.');
    }
  }

  Future<void> _markReview(int wordId) async {
    if (_isActing || _session == null) return;
    setState(() => _isActing = true);
    try {
      final updated = await ApiClient.instance.markWordForReview(_session!.id, wordId);
      if (!mounted) return;
      setState(() {
        _session = updated;
        _isActing = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isActing = false);
      if (e.statusCode == 404) {
        _load();
      } else {
        _showSnack(e.message);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isActing = false);
      _showSnack('Не удалось сохранить. Проверьте соединение.');
    }
  }

  void _showSnack(String text) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LearnedWordsScreen(dictionary: widget.dictionary),
                  ),
                ),
                icon: const Icon(Icons.bookmark_outline),
                label: const Text('Мои изученные слова'),
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Повторить')),
            ],
          ),
        ),
      );
    }

    final session = _session;

    if (session == null) {
      if (_showCountPicker) {
        return _CountPickerView(
          isSubmitting: _isCreating,
          error: _createError,
          onCancel: () => setState(() {
            _showCountPicker = false;
            _createError = null;
          }),
          onSubmit: _createSession,
        );
      }
      return _NoSessionView(
        onStart: () => setState(() {
          _showCountPicker = true;
          _createError = null;
        }),
      );
    }

    if (session.isCompleted || session.currentWord == null) {
      return _CompletedView(
        onAddMore: () => setState(() {
          _session = null;
          _showCountPicker = true;
          _createError = null;
        }),
      );
    }

    return _ActiveSessionView(
      session: session,
      word: session.currentWord!,
      isBusy: _isActing,
      onLearned: () => _markLearned(session.currentWord!.id),
      onReview: () => _markReview(session.currentWord!.id),
    );
  }
}

class _NoSessionView extends StatelessWidget {
  final VoidCallback onStart;
  const _NoSessionView({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.school_outlined, size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            const Text(
              'Изучение слов',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Выберите, сколько новых слов хотите изучить сегодня',
              style: TextStyle(color: Colors.black54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: onStart, child: const Text('Начать изучение')),
          ],
        ),
      ),
    );
  }
}

class _CountPickerView extends StatefulWidget {
  final bool isSubmitting;
  final String? error;
  final VoidCallback onCancel;
  final ValueChanged<int> onSubmit;

  const _CountPickerView({
    required this.isSubmitting,
    required this.error,
    required this.onCancel,
    required this.onSubmit,
  });

  @override
  State<_CountPickerView> createState() => _CountPickerViewState();
}

class _CountPickerViewState extends State<_CountPickerView> {
  int _count = 10;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Сколько слов изучить?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text('От $_minSessionCount до $_maxSessionCount', style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  onPressed: _count > _minSessionCount ? () => setState(() => _count--) : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    '$_count',
                    key: const ValueKey('learning-session-count'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: _count < _maxSessionCount ? () => setState(() => _count++) : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: widget.isSubmitting ? null : () => widget.onSubmit(_count),
              child: widget.isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Начать'),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: widget.isSubmitting ? null : widget.onCancel, child: const Text('Отмена')),
            if (widget.error != null) ...[
              const SizedBox(height: 8),
              Text(widget.error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

class _CompletedView extends StatelessWidget {
  final VoidCallback onAddMore;
  const _CompletedView({required this.onAddMore});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 56),
            const SizedBox(height: 12),
            const Text(
              'Изучение завершено',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: onAddMore, child: const Text('Добавить ещё слов')),
          ],
        ),
      ),
    );
  }
}

class _ActiveSessionView extends StatelessWidget {
  final LearningSession session;
  final GuyoWord word;
  final bool isBusy;
  final VoidCallback onLearned;
  final VoidCallback onReview;

  const _ActiveSessionView({
    required this.session,
    required this.word,
    required this.isBusy,
    required this.onLearned,
    required this.onReview,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _ProgressBar(session: session),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Center(child: _LearningCard(word: word)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isBusy ? null : onReview,
                  child: const Text('Ещё раз буду изучать'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: isBusy ? null : onLearned,
                  child: const Text('Изучил'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final LearningSession session;
  const _ProgressBar({required this.session});

  @override
  Widget build(BuildContext context) {
    final progress = session.totalCount == 0 ? 0.0 : session.learnedCount / session.totalCount;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(value: progress, minHeight: 8),
        ),
        const SizedBox(height: 6),
        Text(
          'Изучено ${session.learnedCount} из ${session.totalCount}',
          style: const TextStyle(color: Colors.black54, fontSize: 13),
        ),
      ],
    );
  }
}

/// The learning flashcard: reuses the GuyoWord model (the exact same Word
/// the dictionary/editor use) but lays it out as a big centered card
/// suited to one-at-a-time study, rather than the compact list row used
/// elsewhere. Every field is optional except `word`/`translation` -- the
/// layout simply omits whatever the current Word doesn't have.
class _LearningCard extends StatelessWidget {
  final GuyoWord word;
  const _LearningCard({required this.word});

  @override
  Widget build(BuildContext context) {
    final hasImage = word.imageUrl != null && word.imageUrl!.isNotEmpty;
    final hasTranscription = word.transcription != null && word.transcription!.isNotEmpty;
    final hasWordAudio = word.wordAudioUrl != null && word.wordAudioUrl!.isNotEmpty;
    final hasTranslationAudio = word.translationAudioUrl != null && word.translationAudioUrl!.isNotEmpty;

    return Container(
      key: ValueKey('learning-card-${word.id}'),
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasImage) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                ApiClient.instance.mediaUrl(word.imageUrl!),
                height: 160,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(height: 0),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  word.word,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
              ),
              if (hasWordAudio) ...[
                const SizedBox(width: 8),
                AudioButton(url: ApiClient.instance.mediaUrl(word.wordAudioUrl!), size: 22),
              ],
            ],
          ),
          if (hasTranscription)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                word.transcription!,
                style: const TextStyle(fontSize: 15, color: Colors.black45),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  word.translation,
                  style: const TextStyle(fontSize: 18),
                  textAlign: TextAlign.center,
                ),
              ),
              if (hasTranslationAudio) ...[
                const SizedBox(width: 8),
                AudioButton(url: ApiClient.instance.mediaUrl(word.translationAudioUrl!), size: 22),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
