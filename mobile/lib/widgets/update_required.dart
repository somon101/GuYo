import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import 'in_app_banner.dart' show appNavigatorKey;

bool _showing = false;

/// The server answered 426: this build is older than it accepts. Shown
/// once at a time, over whatever screen is open.
void showUpdateRequired() {
  final context = appNavigatorKey.currentContext;
  if (context == null || _showing) return;
  _showing = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.system_update_rounded, color: AppColors.primary, size: 36),
      title: Text(tr('Обновите приложение')),
      content: Text(tr('Вышла новая версия GuYo. Чтобы продолжить заниматься, установите её.')),
      actions: [
        FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(tr('Понятно'))),
      ],
    ),
  ).whenComplete(() => _showing = false);
}
