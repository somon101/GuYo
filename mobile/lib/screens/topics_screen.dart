import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/learning_topics.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../widgets/selectable_card.dart';

/// "Мои темы": which goals the user is learning for. Opened from settings,
/// and once, on its own, for accounts that have never been asked. Pops
/// with the saved profile, or null if closed without saving.
class TopicsScreen extends StatefulWidget {
  final List<String> initial;
  final bool firstTime;

  const TopicsScreen({super.key, required this.initial, this.firstTime = false});

  @override
  State<TopicsScreen> createState() => _TopicsScreenState();
}

class _TopicsScreenState extends State<TopicsScreen> {
  late final List<String> _selected = [...widget.initial];
  bool _isSaving = false;
  String? _error;

  void _toggle(String code) {
    setState(() {
      _selected.contains(code) ? _selected.remove(code) : _selected.add(code);
      _error = null;
    });
  }

  Future<void> _save(List<String> topics) async {
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final UserProfile saved = await ApiClient.instance.updateMyProfile(learningTopics: topics);
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = 'Не удалось сохранить. Проверьте интернет.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: !widget.firstTime,
        title: const Text(
          'Мои темы',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
        ),
        iconTheme: const IconThemeData(color: AppColors.primaryDark),
        actions: [
          if (widget.firstTime)
            TextButton(
              key: const ValueKey('topics-skip'),
              onPressed: _isSaving ? null : () => _save(const []),
              child: const Text('Пропустить'),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            const Text(
              'Для чего вы изучаете язык? Можно выбрать несколько — уроки будут начинаться со слов, '
              'которые нужны именно вам.',
              style: TextStyle(fontSize: 14, color: AppColors.secondaryText, height: 1.35),
            ),
            const SizedBox(height: 16),
            for (final goal in learningGoals) ...[
              SelectableCard(
                key: ValueKey('topic-${goal.code}'),
                label: goal.label,
                selected: _selected.contains(goal.code),
                onTap: () => _toggle(goal.code),
              ),
              const SizedBox(height: 10),
            ],
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('topics-save'),
                onPressed: _isSaving ? null : () => _save(_selected),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.pillRadius)),
                ),
                child: Text(_isSaving ? 'Сохранение…' : 'Сохранить'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
