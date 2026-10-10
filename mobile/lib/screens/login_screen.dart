import '../services/google_auth.dart';
import '../widgets/language_picker.dart';
import '../l10n/l10n.dart';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme/app_colors.dart';
import '../widgets/guyo_ui.dart';
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
    } catch (_) {
      if (mounted) setState(() => _error = tr('Не удалось войти через Google'));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LanguagePicker(selected: appLanguage.value, enabled: !_isSubmitting, onSelected: setAppLanguage),
                const SizedBox(height: 20),
                const RoundIconChip(icon: Icons.auto_stories_rounded, size: 64),
                const SizedBox(height: 16),
                Text(
                  'GuYo',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                ),
                const SizedBox(height: 4),
                Text(
                  tr('Вход'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AppColors.secondaryText),
                ),
                const SizedBox(height: 28),
                GuyoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _LoginField(
                        label: tr('Логин'),
                        controller: _loginController,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 14),
                      _LoginField(
                        label: tr('Пароль'),
                        controller: _passwordController,
                        obscure: true,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _isSubmitting ? null : _submit(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(color: AppColors.danger, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.rowRadius)),
                        ),
                        child: _isSubmitting
                            ? SkeletonPulse(
                                child: Text(tr('Входим…'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                              )
                            : Text(tr('Войти'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
                if (googleSignInEnabled) ...[
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    key: const ValueKey('login-google-button'),
                    onPressed: _isSubmitting ? null : _signInWithGoogle,
                    icon: const Text(
                      'G',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF4285F4)),
                    ),
                    label: Text(
                      tr('Войти через Google'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      backgroundColor: AppColors.surface,
                      foregroundColor: AppColors.primaryDark,
                      side: BorderSide(color: AppColors.cardBorder),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.rowRadius)),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(tr('Нет аккаунта?'), style: TextStyle(color: AppColors.secondaryText, fontSize: 13.5)),
                    TextButton(
                      onPressed: _isSubmitting ? null : _openRegister,
                      child: Text(tr('Регистрация'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool obscure;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  const _LoginField({
    required this.label,
    required this.controller,
    this.obscure = false,
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.violetSurface,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppShapes.rowRadius),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
