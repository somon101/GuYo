import '../l10n/l10n.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../api/api_client.dart';
import '../models/dictionary.dart';
import '../models/lesson.dart';
import '../models/word.dart';
import '../widgets/premium_ui.dart';
import '../widgets/ios_ui.dart';
import '../widgets/skeleton.dart';

/// Word selection for a new lesson: either a random count (1-15) or a
/// manual, per-word pick (also capped at 15), grouped by category so
/// browsing is manageable even for a large dictionary. Both modes draw from
/// the SAME pool -- GET /dictionaries/{id}/lesson-candidate-words, every
/// word in this dictionary the user hasn't already learned -- and both
/// ultimately just call POST /lessons, which is the only place a Lesson
/// actually gets created (never client-side). The button says "Начать
/// урок" because that is what it does: the created lesson is popped back
/// to the caller, which runs it immediately (see LessonRunScreen).
class LessonCreateScreen extends StatefulWidget {
  final GuyoDictionary dictionary;
  const LessonCreateScreen({super.key, required this.dictionary});

  @override
  State<LessonCreateScreen> createState() => _LessonCreateScreenState();
}

const int _maxLessonWords = 15;

enum _Mode { random, manual }

class _LessonCreateScreenState extends State<LessonCreateScreen> {
  bool _isLoading = true;
  String? _loadError;
  List<GuyoWord> _candidates = [];

  _Mode _mode = _Mode.random;
  int _randomCount = 5;
  final Set<int> _selectedIds = {};

  bool _isSubmitting = false;
  String? _submitError;

  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  int get _maxCount => _candidates.length < _maxLessonWords ? _candidates.length : _maxLessonWords;

  /// Selects every word of [words] that still fits, or clears them all when
  /// every one is already selected.
  void _toggleAll(List<GuyoWord> words) {
    setState(() {
      final ids = words.map((w) => w.id).toList();
      if (ids.every(_selectedIds.contains)) {
        _selectedIds.removeAll(ids);
      } else {
        for (final id in ids) {
          if (_selectedIds.length >= _maxLessonWords) break;
          _selectedIds.add(id);
        }
      }
    });
  }

  bool _matchesQuery(GuyoWord w) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return w.word.toLowerCase().contains(q) || w.translation.toLowerCase().contains(q);
  }

  void _toggleWord(int wordId) {
    setState(() {
      if (_selectedIds.contains(wordId)) {
        _selectedIds.remove(wordId);
      } else if (_selectedIds.length < _maxLessonWords) {
        _selectedIds.add(wordId);
      }
    });
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final result = await ApiClient.instance.fetchLessonCandidateWords(widget.dictionary.id);
      if (!mounted) return;
      setState(() {
        _candidates = result.words;
        _randomCount = result.words.isEmpty ? 0 : (result.words.length < _maxLessonWords ? result.words.length : _maxLessonWords).clamp(1, _maxLessonWords);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = tr('Не удалось загрузить доступные слова');
      });
    }
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      final Lesson lesson;
      if (_mode == _Mode.random) {
        lesson = await ApiClient.instance.createLesson(dictionaryId: widget.dictionary.id, randomCount: _randomCount);
      } else {
        lesson = await ApiClient.instance.createLesson(dictionaryId: widget.dictionary.id, wordIds: _selectedIds.toList());
      }
      if (!mounted) return;
      // Hands the new lesson back so the caller starts it straight away --
      // "Начать урок" means exactly that, with no stop at the lesson list.
      Navigator.of(context).pop(lesson);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 429) {
        // The daily/weekly lesson limit -- the backend's own wording, plus
        // a way to Premium, rather than an error line under the button.
        setState(() => _isSubmitting = false);
        await showLessonLimitDialog(context, e.message);
        return;
      }
      setState(() {
        _isSubmitting = false;
        _submitError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError = tr('Не удалось создать урок');
      });
    }
  }

  Map<String, List<GuyoWord>> _groupByCategory(List<GuyoWord> words) {
    final groups = <String, List<GuyoWord>>{};
    for (final w in words) {
      final name = (w.categoryName == null || w.categoryName!.isEmpty) ? tr('Без категории') : w.categoryName!;
      groups.putIfAbsent(name, () => []).add(w);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(tr('Новый урок')), backgroundColor: AppColors.canvas),
      body: _buildBody(),
      bottomNavigationBar: _isLoading || _loadError != null || _candidates.isEmpty ? null : _buildSubmitBar(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const SkeletonForm();
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
              FilledButton(onPressed: _load, child: Text(tr('Повторить'))),
            ],
          ),
        ),
      );
    }
    if (_candidates.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            tr('Все доступные слова уже изучены -- новых слов для урока нет.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.secondaryText),
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: IosSegmented<_Mode>(
            value: _mode,
            segments: {_Mode.random: tr('Случайно'), _Mode.manual: tr('Вручную')},
            onChanged: (m) => setState(() => _mode = m),
          ),
        ),
        Expanded(
          child: _mode == _Mode.random ? _buildRandomPicker() : _buildManualPicker(),
        ),
        if (_submitError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(_submitError!, style: const TextStyle(color: AppColors.danger), textAlign: TextAlign.center),
          ),
      ],
    );
  }

  Widget _buildRandomPicker() {
    final maxCount = _maxCount;
    final presets = [5, 10, 15].where((n) => n <= maxCount).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        IosSection(
          header: tr('Количество слов'),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _RoundStepButton(
                        icon: Icons.remove_rounded,
                        onTap: _randomCount > 1 ? () => setState(() => _randomCount--) : null,
                      ),
                      SizedBox(
                        width: 96,
                        child: Text(
                          '$_randomCount',
                          key: const ValueKey('lesson-random-count'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryDark,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      _RoundStepButton(
                        icon: Icons.add_rounded,
                        onTap: _randomCount < maxCount ? () => setState(() => _randomCount++) : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tr('слов в уроке · доступно {0}', [_candidates.length]),
                    style: const TextStyle(fontSize: 13.5, color: AppColors.secondaryText),
                  ),
                  if (presets.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final n in presets)
                          _PresetChip(
                            label: '$n',
                            selected: _randomCount == n,
                            onTap: () => setState(() => _randomCount = n),
                          ),
                        if (!presets.contains(maxCount))
                          _PresetChip(
                            label: tr('Все {0}', [maxCount]),
                            selected: _randomCount == maxCount,
                            onTap: () => setState(() => _randomCount = maxCount),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            tr('Слова возьмём случайно из тех, что вы ещё не выучили.'),
            style: TextStyle(fontSize: 13, color: AppColors.secondaryText),
          ),
        ),
      ],
    );
  }

  Widget _buildManualPicker() {
    final groups = _groupByCategory(_candidates.where(_matchesQuery).toList());
    final full = _selectedIds.length >= _maxLessonWords;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        IosSearchField(
          controller: _search,
          placeholder: tr('Поиск слова или перевода'),
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  tr('Выбрано {0} из {1}', [_selectedIds.length, _maxLessonWords]),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: full ? AppColors.primary : AppColors.secondaryText,
                  ),
                ),
              ),
              if (_selectedIds.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(_selectedIds.clear),
                  child: Text(
                    tr('Сбросить'),
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.primary),
                  ),
                ),
            ],
          ),
        ),
        if (groups.isEmpty)
          Padding(
            padding: EdgeInsets.only(top: 32),
            child: Text(tr('Ничего не найдено'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.secondaryText)),
          ),
        for (final entry in groups.entries) ...[
          IosSection(
            header: '${entry.key} · ${entry.value.length}',
            actionLabel: entry.value.every((w) => _selectedIds.contains(w.id)) ? tr('Снять') : tr('Выбрать все'),
            onAction: () => _toggleAll(entry.value),
            children: [
              for (final word in entry.value)
                IosCheckRow(
                  key: ValueKey('lesson-word-checkbox-${word.id}'),
                  title: word.word,
                  subtitle: word.translation,
                  selected: _selectedIds.contains(word.id),
                  enabled: !full,
                  onTap: () => _toggleWord(word.id),
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }

  Widget _buildSubmitBar() {
    final canSubmit = !_isSubmitting && (_mode == _Mode.random ? _randomCount >= 1 : _selectedIds.isNotEmpty);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        border: Border(top: BorderSide(color: AppColors.cardBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: canSubmit ? _submit : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
              ),
              child: _isSubmitting
                  ? SkeletonPulse(child: Text(tr('Готовим урок…')))
                  : Text(_mode == _Mode.random ? tr('Начать урок') : tr('Начать урок ({0})', [_selectedIds.length])),
            ),
          ),
        ),
      ),
    );
  }
}

/// The round − / + next to the word count.
class _RoundStepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _RoundStepButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return IosPressable(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: enabled ? AppColors.violetSurface : AppColors.progressTrack,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 26, color: enabled ? AppColors.primary : AppColors.muted),
      ),
    );
  }
}

/// A quick-pick amount (5 / 10 / 15) under the counter.
class _PresetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PresetChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IosPressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.violetSurface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.primary,
          ),
        ),
      ),
    );
  }
}
