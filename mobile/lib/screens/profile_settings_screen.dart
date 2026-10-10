import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/learning_topics.dart';
import '../models/user_profile.dart';
import '../services/push_service.dart';
import '../theme/app_colors.dart';
import 'login_screen.dart';
import 'topics_screen.dart';

/// "Настройки": a compact grouped list of what the user may change --
/// personal data, topics, interface language and (for a Russian interface)
/// the language word translations are shown in. Each row opens a small
/// editor and saves on its own through PATCH /users/me/profile; there is no
/// form-wide "Сохранить".
///
/// The photo lives on the profile itself (tap the avatar).
class ProfileSettingsScreen extends StatefulWidget {
  final UserProfile profile;

  const ProfileSettingsScreen({super.key, required this.profile});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

const Color _logoutRed = Color(0xFFE5484D);

const List<({String code, String label})> _translationLanguages = [
  (code: 'tg', label: 'Тоҷикӣ'),
  (code: 'uz', label: 'Oʻzbekcha'),
];

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  late UserProfile _profile;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
  }

  void _showSnack(String text) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  /// One small dialog per row: the given fields, prefilled, and Save.
  /// Returns only when saved or cancelled; a server error (a taken login,
  /// for one) stays in the dialog so nothing typed is lost.
  Future<void> _editFields({
    required String title,
    required List<({String key, String label, String value, TextInputType? keyboard})> fields,
    String? Function(Map<String, String>)? validate,
  }) async {
    final controllers = {for (final f in fields) f.key: TextEditingController(text: f.value)};
    final saved = await showDialog<UserProfile>(
      context: context,
      builder: (dialogContext) {
        String? error;
        var saving = false;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> save() async {
              final values = {for (final e in controllers.entries) e.key: e.value.text.trim()};
              final problem = validate?.call(values);
              if (problem != null) {
                setDialogState(() => error = problem);
                return;
              }
              setDialogState(() {
                saving = true;
                error = null;
              });
              try {
                final profile = await ApiClient.instance.updateMyProfile(
                  login: values['login'],
                  firstName: values['first_name'],
                  lastName: values['last_name'],
                  email: values['email'],
                );
                if (dialogContext.mounted) Navigator.of(dialogContext).pop(profile);
              } on ApiException catch (e) {
                setDialogState(() {
                  saving = false;
                  error = e.message;
                });
              } catch (_) {
                setDialogState(() {
                  saving = false;
                  error = tr('Не удалось сохранить изменения');
                });
              }
            }

            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final f in fields) ...[
                    TextField(
                      controller: controllers[f.key],
                      autofocus: f == fields.first,
                      keyboardType: f.keyboard,
                      textCapitalization:
                          f.keyboard == null ? TextCapitalization.words : TextCapitalization.none,
                      decoration: InputDecoration(labelText: f.label),
                      onSubmitted: (_) => saving ? null : save(),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (error != null)
                    Text(error!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(tr('Отмена'))),
                FilledButton(
                  onPressed: saving ? null : save,
                  child: Text(saving ? tr('Сохранение…') : tr('Сохранить')),
                ),
              ],
            );
          },
        );
      },
    );
    for (final c in controllers.values) {
      c.dispose();
    }
    if (saved != null && mounted) {
      setState(() => _profile = saved);
      _showSnack(tr('Сохранено'));
    }
  }

  Future<String?> _pickOne(String title, List<({String code, String label})> options, String selected) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                title,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
              ),
            ),
            for (final o in options)
              ListTile(
                title: Text(o.label),
                trailing: o.code == selected ? Icon(Icons.check_rounded, color: AppColors.primary) : null,
                onTap: () => Navigator.of(sheetContext).pop(o.code),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Saved to the account first (it decides which translations the
  /// server sends), then applied here -- the app restarts on its home tab.
  Future<void> _changeLanguage() async {
    final code = await _pickOne(tr('Язык интерфейса'), uiLanguages, appLanguage.value);
    if (code == null || code == appLanguage.value) return;
    try {
      await ApiClient.instance.updateMyProfile(uiLanguage: code);
    } catch (_) {
      if (mounted) _showSnack(tr('Не удалось сохранить. Проверьте интернет.'));
      return;
    }
    await setAppLanguage(code);
  }

  Future<void> _changeTranslationLanguage() async {
    final code = await _pickOne(
      tr('Язык перевода'),
      _translationLanguages,
      _profile.translationLanguage,
    );
    if (code == null || code == _profile.translationLanguage) return;
    try {
      final saved = await ApiClient.instance.updateMyProfile(translationLanguage: code);
      if (!mounted) return;
      setState(() => _profile = saved);
      _showSnack(tr('Сохранено'));
    } catch (_) {
      if (mounted) _showSnack(tr('Не удалось сохранить. Проверьте интернет.'));
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Выйти из аккаунта?')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(tr('Отмена'))),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('Выйти'), style: const TextStyle(color: _logoutRed, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await PushService.instance.unregisterCurrentUser();
    await ApiClient.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final fullName = [_profile.firstName, _profile.lastName].where((s) => s != null && s.isNotEmpty).join(' ');
    final topics = [
      for (final goal in learningGoals)
        if ((_profile.learningTopics ?? const []).contains(goal.code)) goal.label,
    ];
    String labelOf(List<({String code, String label})> list, String code) =>
        list.firstWhere((l) => l.code == code, orElse: () => list.first).label;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          tr('Настройки'),
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
        ),
        iconTheme: IconThemeData(color: AppColors.primaryDark),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _Section(
              title: tr('Личные данные'),
              rows: [
                _Row(
                  icon: Icons.alternate_email_rounded,
                  label: tr('Логин'),
                  value: _profile.login,
                  onTap: () => _editFields(
                    title: tr('Логин'),
                    fields: [(key: 'login', label: tr('Логин'), value: _profile.login, keyboard: TextInputType.text)],
                    validate: (v) => v['login']!.length < 3 ? tr('Логин должен быть не короче 3 символов') : null,
                  ),
                ),
                _Row(
                  icon: Icons.person_outline_rounded,
                  label: tr('Имя и фамилия'),
                  value: fullName.isEmpty ? tr('Не указано') : fullName,
                  onTap: () => _editFields(
                    title: tr('Имя и фамилия'),
                    fields: [
                      (key: 'first_name', label: tr('Имя'), value: _profile.firstName ?? '', keyboard: null),
                      (key: 'last_name', label: tr('Фамилия'), value: _profile.lastName ?? '', keyboard: null),
                    ],
                  ),
                ),
                _Row(
                  icon: Icons.mail_outline_rounded,
                  label: tr('Почта'),
                  value: (_profile.email ?? '').isEmpty ? tr('Не указано') : _profile.email!,
                  onTap: null,
                ),
              ],
            ),
            const SizedBox(height: 20),
            _Section(
              title: tr('Обучение'),
              rows: [
                _Row(
                  key: const ValueKey('settings-topics'),
                  icon: Icons.flag_outlined,
                  label: tr('Мои темы'),
                  value: topics.isEmpty ? tr('Не выбраны') : topics.join(', '),
                  onTap: () async {
                    final saved = await Navigator.of(context).push<UserProfile>(
                      MaterialPageRoute(builder: (_) => TopicsScreen(initial: _profile.learningTopics ?? const [])),
                    );
                    if (saved != null && mounted) setState(() => _profile = saved);
                  },
                ),
                _Row(
                  icon: Icons.language_rounded,
                  label: tr('Язык интерфейса'),
                  value: labelOf(uiLanguages, appLanguage.value),
                  onTap: _changeLanguage,
                ),
                // A Tajik or Uzbek interface always reads its own language.
                if (appLanguage.value == 'ru')
                  _Row(
                    icon: Icons.translate_rounded,
                    label: tr('Язык перевода'),
                    value: labelOf(_translationLanguages, _profile.translationLanguage),
                    onTap: _changeTranslationLanguage,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // The account number is shown, never edited: it is permanent.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'ID: ${_profile.publicId}',
                style: TextStyle(fontSize: 13, color: AppColors.secondaryText),
              ),
            ),
            const SizedBox(height: 24),
            // Sign-out lives here, at the very bottom, in red -- where other
            // apps put it -- instead of a "⋮" menu on the home screen.
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppShapes.cardShadow,
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const ValueKey('settings-logout'),
                onTap: _confirmLogout,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.logout_rounded, color: _logoutRed, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        tr('Выйти'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _logoutRed),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A titled white card of rows separated by hairlines.
class _Section extends StatelessWidget {
  final String title;
  final List<Widget> rows;

  const _Section({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: AppColors.secondaryText,
            ),
          ),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppShapes.cardRadius),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, indent: 50, color: AppColors.cardBorder),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Icon, label, current value on the right, chevron.
class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  /// Null for a read-only row (no chevron): the email, which comes from
  /// Google and can't be changed.
  final VoidCallback? onTap;

  const _Row({super.key, required this.icon, required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 22, color: AppColors.primary),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.primaryDark),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: AppColors.secondaryText),
                ),
              ),
              const SizedBox(width: 4),
              if (onTap != null)
                Icon(Icons.chevron_right_rounded, color: AppColors.muted)
              else
                Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
