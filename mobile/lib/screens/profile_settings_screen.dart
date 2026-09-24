import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../widgets/user_avatar.dart';

/// "Настройки": everything about the account the user may change
/// themselves -- login, photo, first name, last name and email.
///
/// Saves through the backend (PATCH /users/me/profile for the fields, the
/// existing avatar endpoints for the photo), never only on the device: the
/// values come back from the server and are what the profile then shows.
///
/// The photo actions are deliberately NOT reimplemented here. Picking and
/// uploading an avatar is a path with hard-won handling for real-device
/// failures (a recreated Activity while the gallery is open, a revoked URI
/// grant, a picker that reports nothing after a visible pick) -- it lives
/// in ProfileScreenState and is passed in, so there is exactly one copy of
/// it.
class ProfileSettingsScreen extends StatefulWidget {
  final UserProfile profile;

  /// Opens the picker and uploads, returning the updated profile, or null
  /// if nothing was picked or the upload failed (the caller reports that
  /// itself).
  final Future<UserProfile?> Function() onPickPhoto;

  /// Clears the photo, returning the updated profile or null on failure.
  final Future<UserProfile?> Function() onRemovePhoto;

  const ProfileSettingsScreen({
    super.key,
    required this.profile,
    required this.onPickPhoto,
    required this.onRemovePhoto,
  });

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  late UserProfile _profile;
  late final TextEditingController _login;
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _email;

  bool _isSaving = false;
  bool _isPhotoBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    _login = TextEditingController(text: _profile.login);
    _firstName = TextEditingController(text: _profile.firstName ?? '');
    _lastName = TextEditingController(text: _profile.lastName ?? '');
    _email = TextEditingController(text: _profile.email ?? '');
  }

  @override
  void dispose() {
    _login.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    super.dispose();
  }

  /// What the user actually changed. Sending only that is what keeps
  /// editing one field from blanking another, and leaves an account that
  /// never had a name alone unless a name was typed.
  Map<String, String> get _changes {
    final changes = <String, String>{};
    void add(String key, String typed, String? current) {
      final value = typed.trim();
      if (value != (current ?? '')) changes[key] = value;
    }

    add('login', _login.text, _profile.login);
    add('first_name', _firstName.text, _profile.firstName);
    add('last_name', _lastName.text, _profile.lastName);
    add('email', _email.text, _profile.email);
    return changes;
  }

  Future<void> _save() async {
    final changes = _changes;
    if (changes.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    if (changes.containsKey('login') && changes['login']!.length < 3) {
      setState(() => _error = 'Логин должен быть не короче 3 символов');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final saved = await ApiClient.instance.updateMyProfile(
        login: changes['login'],
        firstName: changes['first_name'],
        lastName: changes['last_name'],
        email: changes['email'],
      );
      if (!mounted) return;
      setState(() {
        _profile = saved;
        _isSaving = false;
      });
      _showSnack('Сохранено');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        // The backend's own message -- "этот логин уже занят" says far
        // more than any generic failure text could.
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = 'Не удалось сохранить изменения';
      });
    }
  }

  Future<void> _changePhoto() async {
    setState(() => _isPhotoBusy = true);
    final updated = await widget.onPickPhoto();
    if (!mounted) return;
    setState(() {
      _isPhotoBusy = false;
      if (updated != null) _profile = updated;
    });
  }

  Future<void> _removePhoto() async {
    setState(() => _isPhotoBusy = true);
    final updated = await widget.onRemovePhoto();
    if (!mounted) return;
    setState(() {
      _isPhotoBusy = false;
      if (updated != null) _profile = updated;
    });
  }

  void _showSnack(String text) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = _profile.avatarUrl != null && _profile.avatarUrl!.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Настройки',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
        ),
        iconTheme: const IconThemeData(color: AppColors.primaryDark),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _PhotoSection(
              profile: _profile,
              isBusy: _isPhotoBusy,
              hasPhoto: hasPhoto,
              onChange: _isPhotoBusy ? null : _changePhoto,
              onRemove: _isPhotoBusy || !hasPhoto ? null : _removePhoto,
            ),
            const SizedBox(height: 18),
            _Field(
              label: 'Логин',
              hint: 'Как вы входите в приложение',
              controller: _login,
              icon: Icons.alternate_email_rounded,
            ),
            const SizedBox(height: 12),
            _Field(
              label: 'Имя',
              controller: _firstName,
              icon: Icons.person_outline_rounded,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            _Field(
              label: 'Фамилия',
              controller: _lastName,
              icon: Icons.badge_outlined,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            _Field(
              label: 'Электронная почта',
              controller: _email,
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 14),
            // The account number is shown, never edited: it is permanent
            // by definition.
            Row(
              children: [
                const Icon(Icons.tag_rounded, size: 16, color: AppColors.secondaryText),
                const SizedBox(width: 6),
                Text(
                  'ID: ${_profile.publicId}',
                  style: const TextStyle(fontSize: 13, color: AppColors.secondaryText),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: const TextStyle(color: Color(0xFFD03A48), fontSize: 13)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSaving ? null : _save,
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

class _PhotoSection extends StatelessWidget {
  final UserProfile profile;
  final bool isBusy;
  final bool hasPhoto;
  final VoidCallback? onChange;
  final VoidCallback? onRemove;

  const _PhotoSection({
    required this.profile,
    required this.isBusy,
    required this.hasPhoto,
    required this.onChange,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppShapes.cardRadius),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: AppShapes.cardShadow,
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: isBusy ? 0.5 : 1,
                child: UserAvatar(avatarUrl: profile.avatarUrl, login: profile.login, size: 72),
              ),
              if (isBusy) const CircularProgressIndicator(strokeWidth: 2),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Фотография',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                ),
                const SizedBox(height: 2),
                Text(
                  hasPhoto ? 'Ваше фото' : 'Пока используется стандартный аватар',
                  style: const TextStyle(fontSize: 12, color: AppColors.secondaryText),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(onPressed: onChange, child: const Text('Изменить')),
                    if (hasPhoto)
                      TextButton(
                        onPressed: onRemove,
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFFD03A48)),
                        child: const Text('Удалить'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController controller;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;

  const _Field({
    required this.label,
    required this.controller,
    required this.icon,
    this.hint,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.secondaryText),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          style: const TextStyle(fontSize: 15, color: AppColors.primaryDark),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 13, color: AppColors.muted),
            prefixIcon: Icon(icon, size: 20, color: AppColors.primary),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppShapes.rowRadius),
              borderSide: const BorderSide(color: AppColors.cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppShapes.rowRadius),
              borderSide: const BorderSide(color: AppColors.cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppShapes.rowRadius),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
          ),
        ),
      ],
    );
  }
}
