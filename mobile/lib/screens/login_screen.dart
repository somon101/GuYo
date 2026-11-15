import '../services/google_auth.dart';
import '../widgets/google_logo.dart';
import '../widgets/language_picker.dart';
import '../l10n/l10n.dart';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme/app_colors.dart';
import 'home_screen.dart';
import 'register_screen.dart';
import '../widgets/skeleton.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  Future<void> _submit() async {
    // Submitting from the password field's IME action leaves that field's
    // FocusNode holding focus while this whole screen gets replaced -- on
    // some Android keyboards that leaves the system keyboard visibly
    // "stuck" open and docked over every screen afterward, since nothing
    // ever told it to close. Unfocusing before navigating away is what
    // actually dismisses it.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await ApiClient.instance.login(_loginController.text.trim(), _passwordController.text);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = tr('Не удалось подключиться к серверу'));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _openRegister({GoogleSignup? google}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => RegisterScreen(google: google)));
  }

  /// Google account picker -> log in, or the short sign-up for a new one.
  Future<void> _signInWithGoogle() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final idToken = await pickGoogleIdToken();
      if (idToken == null) return; // closed the picker
      final signup = await ApiClient.instance.googleLogin(idToken);
      if (!mounted) return;
      if (signup != null) {
        await _openRegister(google: signup);
        return;
      }
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (error) {
      // Показываем настоящую причину, а не общее «не удалось»: у отказа Google
      // бывает код (например, DEVELOPER_ERROR при несовпадении отпечатка
      // подписи), и без него причину не найти.
      if (mounted) setState(() => _error = '${tr('Не удалось войти через Google')}: $error');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// false: the greeting with the three ways in; true: the two fields.
  bool _showForm = false;

  Widget _button(String label, VoidCallback? onTap, {Key? key, bool filled = true}) => SizedBox(
        height: 52,
        child: FilledButton(
          key: key,
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: filled ? AppColors.primary : AppColors.violetSurface,
            foregroundColor: filled ? Colors.white : AppColors.primaryDark,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      );

  Widget _googleButton() => SizedBox(
        height: 52,
        child: OutlinedButton.icon(
          key: const ValueKey('login-google-button'),
          onPressed: _isSubmitting ? null : _signInWithGoogle,
          icon: const GoogleLogo(size: 20),
          label: Text(tr('Продолжить с Google'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          style: OutlinedButton.styleFrom(
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.primaryDark,
            side: BorderSide(color: AppColors.cardBorder),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      );

  /// The first screen: no fields, only the brand and the three ways in.
  Widget _welcome() => Column(children: [
        const Spacer(),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(22)),
          child: const Icon(Icons.auto_stories_rounded, size: 40, color: Colors.white),
        ),
        const SizedBox(height: 14),
        Text('GuYo', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1, color: AppColors.primary)),
        const SizedBox(height: 2),
        Text(tr('Каждый день по чуть-чуть'), style: TextStyle(fontSize: 15, color: AppColors.secondaryText)),
        const Spacer(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: AppColors.danger, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        _button(tr('Войти'), _isSubmitting ? null : () => setState(() {
              _showForm = true;
              _error = null;
            }), key: const ValueKey('login-start')),
        const SizedBox(height: 12),
        _button(tr('Создать аккаунт'), _isSubmitting ? null : _openRegister, key: const ValueKey('login-register'), filled: false),
        if (googleSignInEnabled) ...[
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: Divider(color: AppColors.cardBorder)),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(tr('или'), style: TextStyle(fontSize: 13, color: AppColors.secondaryText))),
            Expanded(child: Divider(color: AppColors.cardBorder)),
          ]),
          const SizedBox(height: 14),
          _googleButton(),
        ],
        const SizedBox(height: 26),
      ]);

  /// The second step: the login and the password.
  Widget _form() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 14),
        Text(tr('Вход'), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.7, color: AppColors.primaryDark)),
        const SizedBox(height: 18),
        _LoginField(
          key: const ValueKey('login-field-login'),
          label: tr('Логин'),
          icon: Icons.person_outline_rounded,
          controller: _loginController,
          textInputAction: TextInputAction.next,
          hasError: _error != null,
        ),
        const SizedBox(height: 12),
        _LoginField(
          key: const ValueKey('login-field-password'),
          label: tr('Пароль'),
          icon: Icons.lock_outline_rounded,
          controller: _passwordController,
          obscure: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _isSubmitting ? null : _submit(),
          hasError: _error != null,
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 18),
        SizedBox(
          height: 52,
          child: FilledButton(
            key: const ValueKey('login-submit'),
            onPressed: _isSubmitting ? null : _submit,
            style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            child: _isSubmitting
                ? SkeletonPulse(child: Text(tr('Входим…'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)))
                : Text(tr('Войти'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(tr('Нет аккаунта?'), style: TextStyle(color: AppColors.secondaryText, fontSize: 14)),
          TextButton(
            key: const ValueKey('login-register-link'),
            onPressed: _isSubmitting ? null : _openRegister,
            child: Text(tr('Регистрация'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ]),
      ]);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back from the form returns to the greeting instead of leaving the app.
      canPop: !_showForm,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _showForm = false);
      },
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight),
                child: IntrinsicHeight(
                  child: Column(children: [
                    SizedBox(
                      height: 52,
                      child: Row(children: [
                        if (_showForm)
                          IconButton(
                            key: const ValueKey('login-back'),
                            tooltip: tr('Назад'),
                            padding: EdgeInsets.zero,
                            alignment: Alignment.centerLeft,
                            icon: Icon(Icons.arrow_back_rounded, color: AppColors.primaryDark),
                            onPressed: _isSubmitting ? null : () => setState(() => _showForm = false),
                          ),
                        const Spacer(),
                        LanguageChip(selected: appLanguage.value, enabled: !_isSubmitting, onSelected: setAppLanguage),
                      ]),
                    ),
                    Expanded(child: _showForm ? _form() : _welcome()),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginField extends StatefulWidget {
  final String label;
  final IconData icon;
  final TextEditingController controller;
  final bool obscure;
  final bool hasError;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  const _LoginField({
    super.key,
    required this.label,
    required this.icon,
    required this.controller,
    this.obscure = false,
    this.hasError = false,
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  State<_LoginField> createState() => _LoginFieldState();
}

class _LoginFieldState extends State<_LoginField> {
  /// Пароль по умолчанию скрыт, но человек может посмотреть его глазком —
  /// так же, как при регистрации. Текст остаётся тем же, меняется только показ.
  late bool _hidden = widget.obscure;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: widget.hasError ? AppColors.danger : AppColors.cardBorder, width: widget.hasError ? 1.5 : 1),
    );
    return TextField(
      controller: widget.controller,
      obscureText: widget.obscure ? _hidden : false,
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
      style: TextStyle(fontSize: 15.5, color: AppColors.primaryDark),
      decoration: InputDecoration(
        hintText: widget.label,
        hintStyle: TextStyle(color: AppColors.secondaryText),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 17),
        prefixIcon: Icon(widget.icon, size: 20, color: AppColors.secondaryText),
        border: border,
        enabledBorder: border,
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: widget.hasError ? AppColors.danger : AppColors.primary, width: 1.5)),
        suffixIcon: widget.obscure
            ? IconButton(
                key: const ValueKey('login-password-visibility'),
                tooltip: _hidden ? tr('Показать пароль') : tr('Скрыть пароль'),
                icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20, color: AppColors.secondaryText),
                onPressed: () => setState(() => _hidden = !_hidden),
              )
            : null,
      ),
    );
  }
}
