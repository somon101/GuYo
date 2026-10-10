import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../widgets/user_avatar.dart';
import 'scan_friend_screen.dart';

/// "Добавить друга": a compact sheet from the bottom -- scan a QR code
/// (the main way), or type the 9-digit ID; the person found is shown as a
/// card to confirm before anything is added. The user's own small QR sits
/// at the bottom so a friend can scan it right away. Returns true when a
/// friend was added.
Future<bool> showAddFriendSheet(BuildContext context) async {
  final added = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (_) => const _AddFriendSheet(),
  );
  return added == true;
}

/// The found person and an "Добавить в друзья" button -- shared by the
/// sheet and the scanner. Pops true through [onAdded] once added.
Future<bool> confirmAndAddFriend(BuildContext context, FoundUser user) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (_) => _FriendConfirmCard(user: user),
  );
  return ok == true;
}

String errorText(Object e) => e is ApiException ? e.message : tr('Не удалось. Проверьте интернет.');

class _AddFriendSheet extends StatefulWidget {
  const _AddFriendSheet();

  @override
  State<_AddFriendSheet> createState() => _AddFriendSheetState();
}

class _AddFriendSheetState extends State<_AddFriendSheet> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;
  int? _myId = ApiClient.instance.cachedMyProfile()?.publicId;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() => _error = null));
    if (_myId == null) {
      ApiClient.instance.fetchMyProfile().then((p) {
        if (mounted) setState(() => _myId = p.publicId);
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _digits => _controller.text.replaceAll(RegExp(r'\D'), '');

  Future<void> _lookUp() async {
    final id = int.tryParse(_digits);
    if (id == null) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final user = await ApiClient.instance.findUserByPublicId(id);
      if (!mounted) return;
      setState(() => _busy = false);
      if (user.isMe) {
        setState(() => _error = tr('Это ваш собственный ID'));
        return;
      }
      if (await confirmAndAddFriend(context, user) && mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorText(e);
      });
    }
  }

  Future<void> _scan() async {
    final added = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const ScanFriendScreen()));
    if (added == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final ready = _digits.length == 9 && !_busy;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(26)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.muted.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                tr('Добавить друга'),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
              ),
              const SizedBox(height: 2),
              Text(
                tr('Найдите друга по QR-коду или ID'),
                style: TextStyle(fontSize: 13.5, color: AppColors.secondaryText),
              ),
              const SizedBox(height: 16),
              // The main way: scan.
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  key: const ValueKey('scan-friend'),
                  onPressed: _scan,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 22),
                  label: Text(tr('Сканировать QR-код'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: Divider(color: AppColors.cardBorder)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(tr('или'), style: TextStyle(fontSize: 12.5, color: AppColors.secondaryText)),
                  ),
                  Expanded(child: Divider(color: AppColors.cardBorder)),
                ],
              ),
              const SizedBox(height: 14),
              // Or the ID.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('friend-id-field'),
                      controller: _controller,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
                      onSubmitted: (_) => ready ? _lookUp() : null,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AppColors.primaryDark),
                      decoration: InputDecoration(
                        hintText: tr('ID друга, 9 цифр'),
                        hintStyle: TextStyle(fontSize: 15, letterSpacing: 0, fontWeight: FontWeight.w500, color: AppColors.muted),
                        prefixIcon: Icon(Icons.badge_outlined, color: AppColors.secondaryText),
                        filled: true,
                        fillColor: AppColors.violetSurface,
                        contentPadding: const EdgeInsets.symmetric(vertical: 15),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      key: const ValueKey('friend-id-add'),
                      onPressed: ready ? _lookUp : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.progressTrack,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                          : Text(tr('Найти'), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.error_outline_rounded, size: 16, color: AppColors.danger),
                    const SizedBox(width: 6),
                    Expanded(child: Text(_error!, style: TextStyle(fontSize: 13, color: AppColors.danger))),
                  ],
                ),
              ],
              if (_myId != null) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.violetSurface, borderRadius: BorderRadius.circular(18)),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                        child: QrImageView(
                          data: '$_myId',
                          size: 64,
                          padding: EdgeInsets.zero,
                          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF101B63)),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Color(0xFF101B63),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr('Или покажите свой код другу'),
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tr('Ваш ID: {0}', ['$_myId']),
                              style: TextStyle(fontSize: 13, color: AppColors.secondaryText),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The person found, with "Добавить в друзья".
class _FriendConfirmCard extends StatefulWidget {
  final FoundUser user;
  const _FriendConfirmCard({required this.user});

  @override
  State<_FriendConfirmCard> createState() => _FriendConfirmCardState();
}

class _FriendConfirmCardState extends State<_FriendConfirmCard> {
  bool _busy = false;
  String? _error;

  Future<void> _add() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.instance.addFriend(widget.user.publicId);
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(26)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            UserAvatar(avatarUrl: u.avatarUrl, login: u.login, size: 72),
            const SizedBox(height: 10),
            Text(
              u.name,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
            ),
            const SizedBox(height: 2),
            Text('@${u.login}', style: TextStyle(fontSize: 13.5, color: AppColors.secondaryText)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(color: AppColors.violetSurface, borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF5B400)),
                  const SizedBox(width: 4),
                  Text(
                    tr('{0} очков', [u.totalPoints]),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.danger)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: u.isFriend
                  ? OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: Icon(Icons.check_rounded, color: AppColors.success),
                      label: Text(tr('Уже в друзьях'), style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.success.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    )
                  : FilledButton.icon(
                      key: const ValueKey('confirm-add-friend'),
                      onPressed: _busy ? null : _add,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                          : const Icon(Icons.person_add_alt_1_rounded),
                      label: Text(tr('Добавить в друзья'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr('Отмена'), style: TextStyle(color: AppColors.secondaryText)),
            ),
          ],
        ),
      ),
    );
  }
}
