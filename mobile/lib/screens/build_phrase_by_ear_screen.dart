import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/dictionary.dart';
import '../models/phrase.dart';
import '../widgets/glass_backdrop.dart';

const int _roundSize = 10;

/// One instance of a word button, with a unique id so two identical tokens
/// in the same phrase (e.g. "I want to go to school" has "to" twice) are
/// always distinguishable and independently tappable -- never merged or
/// treated as one element. Same convention as BuildWordScreen's own letter
/// tiles.
class _WordTile {
  final String id;
  final String text;
  const _WordTile(this.id, this.text);
}

class _ListenTask {
  final GuyoPhrase phrase;
  final List<String> originalTokens; // exact surface form, in the phrase's own order
  final List<_WordTile> shuffledTiles;
  const _ListenTask({required this.phrase, required this.originalTokens, required this.shuffledTiles});
}

/// "Собери фразу на слух": listen to a phrase's own recording, then
/// reassemble it from its shuffled words -- a listening-comprehension drill,
/// as one of the "Практика" exercises.
///
/// The phrase pool is exactly ApiClient.fetchAvailablePhrases (the same
/// already-learned-words-based availability "Мои фразы" and "Собери фразу"
/// use) -- never a separate/parallel definition of what's available. Each
/// task's correct tokens come directly from that Phrase's own `original`
/// text, split on whitespace and kept EXACTLY as written (no stripping, no
/// swap to a word's base dictionary form) -- a phrase's own grammar chose
/// that surface form, and reproducing it is the whole point of the drill.
/// Only phrases with their own recording are offered, since there is
/// nothing to listen to otherwise.
///
/// Deliberately has no score/progress of its own, same as BuildPhraseScreen:
/// this is Practice, not a Lesson -- nothing here reports to the backend or
/// touches WordProgress. No Word/Phrase copy is ever created; everything is
/// addressed by the same existing phrase_id.
class BuildPhraseByEarScreen extends StatefulWidget {
  final GuyoDictionary dictionary;
  const BuildPhraseByEarScreen({super.key, required this.dictionary});

  @override
  State<BuildPhraseByEarScreen> createState() => _BuildPhraseByEarScreenState();
}

class _BuildPhraseByEarScreenState extends State<BuildPhraseByEarScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<_ListenTask> _tasks = [];

  int _index = 0;
  int _correctCount = 0;
  List<_WordTile> _pool = [];
  List<_WordTile> _assembled = [];
  bool _isEvaluated = false;
  bool _isCorrect = false;
  bool _isLocked = false;

  final _player = AudioPlayer();
  bool _isPlayingAudio = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final phrases = await ApiClient.instance.fetchAvailablePhrases(widget.dictionary.id);
      final random = Random();
      final shuffledPhrases = List<GuyoPhrase>.from(phrases)..shuffle(random);

      final tasks = <_ListenTask>[];
      for (final phrase in shuffledPhrases) {
        if (tasks.length >= _roundSize) break;
        final audioUrl = phrase.originalAudioUrl;
        if (audioUrl == null || audioUrl.isEmpty) continue; // nothing to listen to
        final tokens = phrase.original.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
        if (tokens.length < 2) continue; // nothing meaningful to reorder
        final tiles = [for (var i = 0; i < tokens.length; i++) _WordTile('$i-${tokens[i]}', tokens[i])]
          ..shuffle(random);
        tasks.add(_ListenTask(phrase: phrase, originalTokens: tokens, shuffledTiles: tiles));
      }

      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _index = 0;
        _correctCount = 0;
        _isLoading = false;
      });
      if (tasks.isNotEmpty) _startTask(0);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Не удалось загрузить упражнение';
      });
    }
  }

  void _startTask(int index) {
    final task = _tasks[index];
    setState(() {
      _index = index;
      _pool = List<_WordTile>.from(task.shuffledTiles);
      _assembled = [];
      _isEvaluated = false;
      _isCorrect = false;
      _isLocked = false;
    });
    _playAudio();
  }

  Future<void> _playAudio() async {
    final url = _tasks[_index].phrase.originalAudioUrl;
    if (url == null || url.isEmpty) return;
    try {
      await _player.stop();
      if (!mounted) return;
      setState(() => _isPlayingAudio = true);
      await _player.play(UrlSource(ApiClient.instance.mediaUrl(url)));
      _player.onPlayerComplete.first.then((_) {
        if (mounted) setState(() => _isPlayingAudio = false);
      });
    } catch (_) {
      if (mounted) setState(() => _isPlayingAudio = false);
    }
  }

  void _tapPoolTile(_WordTile tile) {
    if (_isLocked) return;
    setState(() {
      _pool = _pool.where((t) => t.id != tile.id).toList();
      _assembled = [..._assembled, tile];
    });
    if (_pool.isEmpty) _evaluate();
  }

  void _tapAssembledTile(_WordTile tile) {
    if (_isLocked) return;
    setState(() {
      _assembled = _assembled.where((t) => t.id != tile.id).toList();
      _pool = [..._pool, tile];
    });
  }

  void _evaluate() {
    final original = _tasks[_index].originalTokens;
    final assembledText = _assembled.map((t) => t.text).toList();
    final correct = listEquals(assembledText, original);
    setState(() {
      _isEvaluated = true;
      _isCorrect = correct;
      _isLocked = true;
      if (correct) _correctCount++;
    });
    Future.delayed(const Duration(milliseconds: 950), () {
      if (!mounted) return;
      _advance();
    });
  }

  void _advance() {
    if (_index + 1 < _tasks.length) {
      _startTask(_index + 1);
    } else {
      setState(() => _index = _tasks.length); // past the last index marks completion
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Собери фразу на слух'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: GlassBackdrop(child: SafeArea(child: _buildBody())),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Повторить')),
            ],
          ),
        ),
      );
    }
    if (_tasks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.headphones_outlined, size: 48, color: Colors.indigo.shade300),
              const SizedBox(height: 16),
              const Text(
                'Пока недостаточно данных для практики',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Нужны доступные фразы из 2+ слов с озвучкой. Изучите больше слов, чтобы открыть их.',
                style: TextStyle(color: Colors.black54),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_index >= _tasks.length) {
      return _RoundCompleteView(correctCount: _correctCount, total: _tasks.length, onPlayAgain: _load);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 90, 16, 16),
      child: Column(
        children: [
          _ProgressHeader(current: _index + 1, total: _tasks.length, correctCount: _correctCount),
          const SizedBox(height: 16),
          _ListenCard(
            key: ValueKey('build-phrase-by-ear-listen-${_tasks[_index].phrase.id}'),
            isPlaying: _isPlayingAudio,
            onReplay: _playAudio,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _AssembledArea(
                    key: const ValueKey('build-phrase-by-ear-assembled'),
                    tiles: _assembled,
                    originalTokens: _tasks[_index].originalTokens,
                    isEvaluated: _isEvaluated,
                    onTapTile: _tapAssembledTile,
                  ),
                  const SizedBox(height: 8),
                  if (_isEvaluated) ...[
                    const SizedBox(height: 8),
                    _ResultBanner(isCorrect: _isCorrect, translation: _tasks[_index].phrase.translationTg),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    key: const ValueKey('build-phrase-by-ear-pool'),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tile in _pool)
                          _WordChip(key: ValueKey(tile.id), text: tile.text, onTap: () => _tapPoolTile(tile)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  final int current;
  final int total;
  final int correctCount;
  const _ProgressHeader({required this.current, required this.total, required this.correctCount});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Фраза $current из $total',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54),
            ),
            Row(
              children: [
                const Icon(Icons.check_circle, size: 15, color: Colors.green),
                const SizedBox(width: 4),
                Text('$correctCount', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(value: current / total, minHeight: 6, backgroundColor: Colors.indigo.shade50),
        ),
      ],
    );
  }
}

/// The one glass-treated surface on screen: a compact "what to listen to"
/// card, dominated by a single big replay control -- deliberately the only
/// prominent element, since listening comes first in the task.
class _ListenCard extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onReplay;
  const _ListenCard({super.key, required this.isPlaying, required this.onReplay});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      child: InkWell(
        onTap: onReplay,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.2),
            boxShadow: [
              BoxShadow(color: Colors.indigo.withValues(alpha: 0.08), blurRadius: 18, offset: const Offset(0, 8)),
            ],
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: isPlaying
                        ? [Colors.indigo.shade300, Colors.indigo.shade500]
                        : [Colors.indigo.shade400, Colors.indigo.shade700],
                  ),
                ),
                child: Icon(isPlaying ? Icons.graphic_eq : Icons.volume_up_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Прослушать ещё раз',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87),
                ),
              ),
              Icon(Icons.replay_rounded, color: Colors.indigo.shade400, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sentence being built, in the user's chosen order -- empty state is a
/// dashed placeholder so it's clear this area is where tapped words land.
class _AssembledArea extends StatelessWidget {
  final List<_WordTile> tiles;
  final List<String> originalTokens;
  final bool isEvaluated;
  final ValueChanged<_WordTile> onTapTile;

  const _AssembledArea({
    super.key,
    required this.tiles,
    required this.originalTokens,
    required this.isEvaluated,
    required this.onTapTile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.indigo.withValues(alpha: 0.15),
          width: 1.2,
        ),
      ),
      child: tiles.isEmpty
          ? const Center(
              child: Text('Соберите фразу из слов ниже', style: TextStyle(color: Colors.black38, fontSize: 13)),
            )
          : Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 8,
              children: [
                for (var i = 0; i < tiles.length; i++)
                  _WordChip(
                    text: tiles[i].text,
                    onTap: isEvaluated ? null : () => onTapTile(tiles[i]),
                    state: !isEvaluated
                        ? _ChipState.placed
                        : (i < originalTokens.length && tiles[i].text == originalTokens[i])
                            ? _ChipState.correct
                            : _ChipState.incorrect,
                  ),
              ],
            ),
    );
  }
}

enum _ChipState { normal, placed, correct, incorrect }

class _WordChip extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final _ChipState state;
  const _WordChip({super.key, required this.text, required this.onTap, this.state = _ChipState.normal});

  @override
  Widget build(BuildContext context) {
    Color background;
    Color border;
    Color textColor = Colors.black87;
    switch (state) {
      case _ChipState.normal:
        background = Colors.white.withValues(alpha: 0.85);
        border = Colors.indigo.withValues(alpha: 0.18);
      case _ChipState.placed:
        background = Colors.indigo.withValues(alpha: 0.1);
        border = Colors.indigo.shade300;
      case _ChipState.correct:
        background = Colors.green.shade50;
        border = Colors.green.shade400;
        textColor = Colors.green.shade800;
      case _ChipState.incorrect:
        background = Colors.red.shade50;
        border = Colors.red.shade300;
        textColor = Colors.red.shade800;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border, width: 1.3),
            ),
            child: Text(text, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textColor)),
          ),
        ),
      ),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  final bool isCorrect;
  final String translation;
  const _ResultBanner({required this.isCorrect, required this.translation});

  @override
  Widget build(BuildContext context) {
    final color = isCorrect ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.shade200),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(isCorrect ? Icons.check_circle : Icons.cancel, color: color.shade600, size: 18),
              const SizedBox(width: 6),
              Text(
                isCorrect ? 'Правильно' : 'Неправильный порядок',
                style: TextStyle(fontWeight: FontWeight.w700, color: color.shade800, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(translation, style: const TextStyle(fontSize: 13, color: Colors.black54), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _RoundCompleteView extends StatelessWidget {
  final int correctCount;
  final int total;
  final VoidCallback onPlayAgain;
  const _RoundCompleteView({required this.correctCount, required this.total, required this.onPlayAgain});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
            boxShadow: [
              BoxShadow(color: Colors.indigo.withValues(alpha: 0.1), blurRadius: 24, offset: const Offset(0, 10)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.emoji_events_outlined, color: Colors.amber.shade600, size: 48),
              const SizedBox(height: 12),
              const Text('Практика завершена!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('Правильно: $correctCount из $total', style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 22),
              FilledButton.icon(onPressed: onPlayAgain, icon: const Icon(Icons.refresh), label: const Text('Играть ещё раз')),
            ],
          ),
        ),
      ),
    );
  }
}
