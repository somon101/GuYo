import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/app_colors.dart';

/// A time of day the user chose to study, minutes since midnight. The
/// server sends a reminder at each enabled one (and one follow-up after
/// the day's last if nothing was answered since).
class StudyTime {
  final int minute;
  final bool enabled;
  const StudyTime(this.minute, {this.enabled = true});

  factory StudyTime.fromJson(Map<String, dynamic> json) =>
      StudyTime(json['minute_of_day'] as int, enabled: json['enabled'] as bool? ?? true);

  Map<String, dynamic> toJson() => {'minute_of_day': minute, 'enabled': enabled};

  StudyTime copyWith({int? minute, bool? enabled}) => StudyTime(minute ?? this.minute, enabled: enabled ?? this.enabled);
}

const int maxStudyTimes = 5;

String formatStudyMinute(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

/// "08:00, 20:00" for a settings row; enabled times only.
String studyTimesSummary(List<StudyTime> times) {
  final on = times.where((t) => t.enabled).map((t) => formatStudyMinute(t.minute)).toList();
  return on.isEmpty ? tr('Не выбрано') : on.join(', ');
}

const _presets = [
  (emoji: '🌅', label: 'Утро', minute: 8 * 60),
  (emoji: '☀️', label: 'День', minute: 13 * 60),
  (emoji: '🌙', label: 'Вечер', minute: 20 * 60),
];

/// Quick picks (morning / day / evening), the chosen times as rows (tap to
/// change, × to remove, optionally an on/off switch), and «Своё время».
/// Stateless: the owner keeps the list and decides when to save it.
class StudyTimesEditor extends StatelessWidget {
  final List<StudyTime> times;
  final ValueChanged<List<StudyTime>> onChanged;

  /// Settings show a switch per time; registration does not need one.
  final bool showSwitches;

  const StudyTimesEditor({super.key, required this.times, required this.onChanged, this.showSwitches = false});

  List<StudyTime> _sorted(Iterable<StudyTime> list) => list.toList()..sort((a, b) => a.minute.compareTo(b.minute));

  bool _has(int minute) => times.any((t) => t.minute == minute);

  void _togglePreset(int minute) {
    if (_has(minute)) {
      onChanged(times.where((t) => t.minute != minute).toList());
    } else if (times.length < maxStudyTimes) {
      onChanged(_sorted([...times, StudyTime(minute)]));
    }
  }

  Future<void> _addCustom(BuildContext context) async {
    final minute = await pickStudyTime(context, 18 * 60);
    if (minute == null || _has(minute)) return;
    onChanged(_sorted([...times, StudyTime(minute)]));
  }

  Future<void> _edit(BuildContext context, StudyTime time) async {
    final minute = await pickStudyTime(context, time.minute);
    if (minute == null || minute == time.minute || _has(minute)) return;
    onChanged(_sorted(times.map((t) => t == time ? t.copyWith(minute: minute) : t)));
  }

  @override
  Widget build(BuildContext context) {
    final full = times.length >= maxStudyTimes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 0; i < _presets.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _PresetChip(
                  key: ValueKey('study-preset-${_presets[i].minute}'),
                  emoji: _presets[i].emoji,
                  label: tr(_presets[i].label),
                  time: formatStudyMinute(_presets[i].minute),
                  selected: _has(_presets[i].minute),
                  onTap: () => _togglePreset(_presets[i].minute),
                ),
              ),
            ],
          ],
        ),
        if (times.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppShapes.cardRadius),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(
              children: [
                for (var i = 0; i < times.length; i++) ...[
                  if (i > 0) Divider(height: 1, indent: 50, color: AppColors.cardBorder),
                  _TimeRow(
                    time: times[i],
                    showSwitch: showSwitches,
                    onTap: () => _edit(context, times[i]),
                    onToggle: (on) => onChanged([for (final t in times) t == times[i] ? t.copyWith(enabled: on) : t]),
                    onRemove: () => onChanged(times.where((t) => t != times[i]).toList()),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('study-add-custom'),
            onPressed: full ? null : () => _addCustom(context),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: Text(
              full ? tr('Не больше 5 времён') : tr('Своё время'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String emoji;
  final String label;
  final String time;
  final bool selected;
  final VoidCallback onTap;

  const _PresetChip({
    super.key,
    required this.emoji,
    required this.label,
    required this.time,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.violetSurface : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShapes.cardRadius),
        side: BorderSide(color: selected ? AppColors.primary : AppColors.cardBorder, width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppShapes.cardRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
              ),
              Text(
                time,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.primary : AppColors.secondaryText,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  final StudyTime time;
  final bool showSwitch;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRemove;

  const _TimeRow({
    required this.time,
    required this.showSwitch,
    required this.onTap,
    required this.onToggle,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final active = !showSwitch || time.enabled;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
          child: Row(
            children: [
              Icon(Icons.alarm_rounded, size: 22, color: active ? AppColors.primary : AppColors.muted),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  formatStudyMinute(time.minute),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: active ? AppColors.primaryDark : AppColors.muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (showSwitch)
                CupertinoSwitch(value: time.enabled, activeTrackColor: AppColors.primary, onChanged: onToggle),
              IconButton(
                onPressed: onRemove,
                tooltip: tr('Удалить'),
                icon: Icon(Icons.close_rounded, size: 20, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An iOS-style hour/minute wheel in a bottom sheet. Null when dismissed.
Future<int?> pickStudyTime(BuildContext context, int initialMinute) {
  var picked = initialMinute ~/ 5 * 5;
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr('Время занятий'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
            ),
            SizedBox(
              height: 200,
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  brightness: AppColors.dark ? Brightness.dark : Brightness.light,
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: TextStyle(fontSize: 22, color: AppColors.primaryDark),
                  ),
                ),
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  use24hFormat: true,
                  minuteInterval: 5,
                  initialDateTime: DateTime(2000, 1, 1, picked ~/ 60, picked % 60),
                  onDateTimeChanged: (d) => picked = d.hour * 60 + d.minute,
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(picked),
              child: Text(tr('Готово')),
            ),
          ],
        ),
      ),
    ),
  );
}
