import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../widgets/in_app_banner.dart';
import '../widgets/study_times_editor.dart';

/// Settings → «Время занятий». Every change saves on its own, like the
/// other settings rows; pops with the stored list.
class StudyTimesScreen extends StatefulWidget {
  final List<StudyTime> initial;
  const StudyTimesScreen({super.key, required this.initial});

  @override
  State<StudyTimesScreen> createState() => _StudyTimesScreenState();
}

class _StudyTimesScreenState extends State<StudyTimesScreen> {
  late List<StudyTime> _times = widget.initial;
  int _saveSeq = 0;

  Future<void> _change(List<StudyTime> next) async {
    final previous = _times;
    setState(() => _times = next);
    final seq = ++_saveSeq;
    try {
      final saved = await ApiClient.instance.saveStudyTimes(next);
      if (mounted && seq == _saveSeq) setState(() => _times = saved);
    } catch (_) {
      if (!mounted || seq != _saveSeq) return;
      setState(() => _times = previous);
      InAppBanner.show(body: tr('Не удалось сохранить. Проверьте интернет.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_times);
      },
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(
          backgroundColor: AppColors.canvas,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Text(
            tr('Время занятий'),
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
          ),
          iconTheme: IconThemeData(color: AppColors.primaryDark),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
                child: Text(
                  tr('В это время придёт напоминание. Если вы не зайдёте, через какое-то время придёт ещё одно.'),
                  style: TextStyle(fontSize: 14, color: AppColors.secondaryText),
                ),
              ),
              StudyTimesEditor(times: _times, showSwitches: true, onChanged: _change),
            ],
          ),
        ),
      ),
    );
  }
}
