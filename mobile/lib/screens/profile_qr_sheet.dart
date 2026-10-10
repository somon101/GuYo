import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/l10n.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../widgets/user_avatar.dart';

/// The user's own QR card: a compact floating sheet with their avatar,
/// name, a QR code that encodes their public ID (the 9-digit number the
/// profile shows), the GuYo mark in its centre, and the ID itself with a
/// copy button underneath.
Future<void> showProfileQr(BuildContext context, UserProfile profile) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    isScrollControlled: true,
    builder: (_) => _ProfileQrSheet(profile: profile),
  );
}

class _ProfileQrSheet extends StatelessWidget {
  final UserProfile profile;
  const _ProfileQrSheet({required this.profile});

  @override
  Widget build(BuildContext context) {
    final id = '${profile.publicId}';
    final name = [profile.firstName, profile.lastName].where((s) => s != null && s.isNotEmpty).join(' ');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: AppColors.dark ? [AppColors.surface, AppColors.violetSurface] : const [Colors.white, Color(0xFFEEF0FC)],
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      UserAvatar(avatarUrl: profile.avatarUrl, login: profile.login, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name.isEmpty ? profile.login : name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                            ),
                            Text(
                              '@${profile.login}',
                              style: TextStyle(fontSize: 13, color: AppColors.secondaryText),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: tr('Закрыть'),
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close_rounded, color: AppColors.secondaryText),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: AppColors.primary.withValues(alpha: 0.10), blurRadius: 20, offset: const Offset(0, 6)),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        QrImageView(
                          key: const ValueKey('profile-qr-code'),
                          data: id,
                          size: 210,
                          padding: EdgeInsets.zero,
                          // High correction keeps it scannable under the logo.
                          errorCorrectionLevel: QrErrorCorrectLevel.H,
                          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF101B63)),
                          dataModuleStyle: QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Color(0xFF101B63), // always dark on the white box: scannable in both themes
                          ),
                        ),
                        Container(
                          width: 54,
                          height: 54,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: Image.asset('assets/icon/guyo_icon.png', fit: BoxFit.cover),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: id));
                        HapticFeedback.selectionClick();
                        ScaffoldMessenger.maybeOf(context)
                            ?.showSnackBar(SnackBar(content: Text(tr('ID скопирован')), duration: const Duration(seconds: 2)));
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'ID: $id',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.6,
                                color: AppColors.secondaryText,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.copy_rounded, size: 16, color: AppColors.secondaryText),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tr('Покажите код другу, чтобы он нашёл вас в GuYo'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
