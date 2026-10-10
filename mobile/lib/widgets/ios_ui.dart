import '../l10n/l10n.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// iOS-style building blocks, drawn in GuYo's own palette: the sliding
/// segmented control, grouped inset sections, check rows, a search field
/// and the press-to-shrink feel every tappable tile shares. Built on the
/// Cupertino widgets Flutter already ships -- no extra package.

/// Hairline between rows inside an [IosSection].
Color get _separator => AppColors.separator;

/// `CupertinoSlidingSegmentedControl` in the app's colors.
class IosSegmented<T extends Object> extends StatelessWidget {
  final T value;
  final Map<T, String> segments;
  final ValueChanged<T> onChanged;

  const IosSegmented({super.key, required this.value, required this.segments, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: CupertinoSlidingSegmentedControl<T>(
        groupValue: value,
        backgroundColor: AppColors.progressTrack,
        thumbColor: Colors.white,
        padding: const EdgeInsets.all(3),
        onValueChanged: (v) {
          if (v == null) return;
          HapticFeedback.selectionClick();
          onChanged(v);
        },
        children: {
          for (final entry in segments.entries)
            entry.key: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Text(
                entry.value,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: entry.key == value ? FontWeight.w700 : FontWeight.w500,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
        },
      ),
    );
  }
}

/// A grouped, inset list section: an optional small uppercase header (with
/// an optional action on its right, e.g. "Выбрать все"), then a white
/// rounded block whose rows are separated by hairlines.
class IosSection extends StatelessWidget {
  final String? header;
  final String? actionLabel;
  final VoidCallback? onAction;
  final List<Widget> children;

  const IosSection({super.key, this.header, this.actionLabel, this.onAction, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    header!.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12.5,
                      letterSpacing: 0.4,
                      fontWeight: FontWeight.w600,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ),
                if (actionLabel != null)
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                    onPressed: onAction,
                    child: Text(
                      actionLabel!,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.primary),
                    ),
                  ),
              ],
            ),
          ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: AppShapes.cardShadow,
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) Divider(height: 0.6, thickness: 0.6, indent: 16, color: _separator),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One selectable row: a title, an optional grey subtitle, and an iOS
/// round check on the right.
class IosCheckRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool selected;

  /// Greyed out and not tappable -- e.g. the lesson is already full.
  final bool enabled;
  final VoidCallback onTap;

  const IosCheckRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.selected,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = enabled || selected;
    return Opacity(
      opacity: active ? 1 : 0.4,
      child: InkWell(
        onTap: active
            ? () {
                HapticFeedback.selectionClick();
                onTap();
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.primaryDark),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle!, style: TextStyle(fontSize: 13.5, color: AppColors.secondaryText)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IosCheckCircle(selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

/// The round check mark iOS uses for multi-select lists.
class IosCheckCircle extends StatelessWidget {
  final bool selected;
  const IosCheckCircle({super.key, required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppColors.primary : Colors.transparent,
        border: Border.all(color: selected ? AppColors.primary : AppColors.muted, width: 1.6),
      ),
      child: selected ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
    );
  }
}

/// `CupertinoSearchTextField` on a white field.
class IosSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String placeholder;

  IosSearchField({super.key, required this.controller, required this.onChanged, String? placeholder}) : placeholder = placeholder ?? tr('Поиск');

  @override
  Widget build(BuildContext context) {
    return CupertinoSearchTextField(
      controller: controller,
      onChanged: onChanged,
      placeholder: placeholder,
      backgroundColor: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      style: TextStyle(fontSize: 16, color: AppColors.primaryDark),
      placeholderStyle: TextStyle(fontSize: 16, color: AppColors.muted),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
    );
  }
}

/// The press feel every tappable tile in the app shares: shrinks a little
/// while held and gives a light haptic tick on tap. Wraps the tile's own
/// look; the tile decides what it shows, this only decides how it reacts.
class IosPressable extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;

  const IosPressable({super.key, required this.onTap, required this.child});

  @override
  State<IosPressable> createState() => _IosPressableState();
}

class _IosPressableState extends State<IosPressable> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    // Its own button node, so screen readers (and web semantics) see each
    // tile as one tappable button labelled by its text.
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      child: _gesture(enabled),
    );
  }

  Widget _gesture(bool enabled) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
