import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../theme/app_colors.dart';
import '../widgets/guyo_ui.dart';
import 'home_screen.dart';
import 'register_screen.dart';

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
      await ApiClient.instance.login(
        _loginController.text.trim(),
        _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Не удалось подключиться к серверу');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _openRegister() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
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
                const RoundIconChip(icon: Icons.auto_stories_rounded, size: 64),
                const SizedBox(height: 16),
                const Text(
                  'GuYo',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Вход',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AppColors.secondaryText),
                ),
                const SizedBox(height: 28),
                GuyoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _LoginField(label: 'Логин', controller: _loginController, textInputAction: TextInputAction.next),
                      const SizedBox(height: 14),
                      _LoginField(
                        label: 'Пароль',
                        controller: _passwordController,
                        obscure: true,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _isSubmitting ? null : _submit(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(color: AppColors.danger, fontSize: 13, fontWeight: FontWeight.w600),
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
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Войти', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Нет аккаунта?', style: TextStyle(color: AppColors.secondaryText, fontSize: 13.5)),
                    TextButton(
                      onPressed: _isSubmitting ? null : _openRegister,
                      child: const Text('Регистрация', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
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
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
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
