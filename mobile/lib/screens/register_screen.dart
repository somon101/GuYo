import '../l10n/l10n.dart';
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/dictionary.dart';
import '../theme/app_colors.dart';
import '../widgets/guyo_ui.dart';
import 'home_screen.dart';
import '../models/learning_topics.dart';
import '../widgets/selectable_card.dart';
import '../widgets/skeleton.dart';

/// GuYo's self-registration: one continuous, compact wizard rather than a
/// single giant form -- language, then account details, then age, goal
/// and how the person found GuYo. Nothing is sent to the backend until
/// the very last step; every field already typed stays in memory across
/// Next/Back the whole time (see _RegisterScreenState's own fields --
/// plain TextEditingControllers and selections, never rebuilt per step).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}


List<({String code, String label})> get _ageGroups => [
  (code: '12-17', label: tr('12–17 лет')),
  (code: '18-24', label: tr('18–24 года')),
  (code: '25+', label: tr('25+ лет')),
];

List<({String code, String label})> get _referralSources => [
  (code: 'social', label: tr('Социальные сети')),
  (code: 'youtube', label: 'YouTube'),
  (code: 'telegram', label: 'Telegram'),
  (code: 'search', label: tr('Поисковик')),
  (code: 'friends', label: tr('От друзей или знакомых')),
  (code: 'ads', label: tr('Реклама')),
  (code: 'other', label: tr('Другое')),
];

class _RegisterScreenState extends State<RegisterScreen> {
  int _step = 0;

  /// The wizard's steps in order. A Russian interface also asks which
  /// language word translations are shown in; a Tajik or Uzbek one already
  /// reads its own.
  List<String> get _steps => [
        'language',
        if (appLanguage.value == 'ru') 'translation',
        'account',
        'age',
        'goal',
        'referral',
      ];

  String get _stepKey => _steps[_step];

  // --- Translation language (Russian interface only) ----------------------
  String _translationLanguage = 'tg';

  // --- Step 0: language ---------------------------------------------------
  bool _isLoadingLanguages = true;
  String? _languagesError;
  List<GuyoDictionary> _languages = [];
  String? _selectedLanguage;
  bool _showAllLanguages = false;

  // --- Step 1: account -----------------------------------------------------
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _loginCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _firstNameError;
  String? _lastNameError;
  String? _emailError;
  String? _loginError;
  String? _passwordError;
  String? _confirmError;

  // --- Step 2/3/4: single-choice picks --------------------------------------
  String? _ageGroup;
  final List<String> _learningGoals = [];
  String? _referralSource;

  bool _isSubmitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _loadLanguages();
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _loginCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLanguages() async {
    setState(() {
      _isLoadingLanguages = true;
      _languagesError = null;
    });
    try {
      final fetched = await ApiClient.instance.fetchPublicDictionaries();
      if (!mounted) return;
      // One entry per language, first-seen order -- same rule
      // HomeScreen's own switcher already applies (see _languageOptions
      // there), never a second "which languages exist" system.
      final seen = <String>{};
      final deduped = <GuyoDictionary>[];
      for (final d in fetched) {
        if (seen.add(d.language)) deduped.add(d);
      }
      setState(() {
        _languages = deduped;
        _isLoadingLanguages = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingLanguages = false;
        _languagesError = tr('Не удалось загрузить список языков. Проверьте интернет.');
      });
    }
  }

  bool get _canAdvance {
    switch (_stepKey) {
      case 'language':
        return _selectedLanguage != null;
      case 'translation':
        return true;
      case 'account':
        return true; // this step validates its own fields on Next
      case 'age':
        return _ageGroup != null;
      case 'goal':
        return _learningGoals.isNotEmpty;
      case 'referral':
        return _referralSource != null;
    }
    return false;
  }

  void _goBack() {
    if (_step == 0) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _step -= 1);
  }

  void _goNext() {
    if (_stepKey == 'account' && !_validateAccountStep()) {
      return;
    }
    if (_step < _steps.length - 1) {
      setState(() => _step += 1);
    } else {
      _submit();
    }
  }

  bool _validateAccountStep() {
    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final login = _loginCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;

    final emailLooksValid = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);

    setState(() {
      _firstNameError = firstName.isEmpty ? tr('Введите имя') : null;
      _lastNameError = lastName.isEmpty ? tr('Введите фамилию') : null;
      _emailError = email.isEmpty
          ? tr('Введите email')
          : (!emailLooksValid ? tr('Некорректный email') : null);
      _loginError = login.isEmpty
          ? tr('Введите логин')
          : (login.length < 3 ? tr('Минимум 3 символа') : null);
      _passwordError = password.isEmpty
          ? tr('Введите пароль')
          : (password.length < 4 ? tr('Минимум 4 символа') : null);
      _confirmError = confirm.isEmpty
          ? tr('Повторите пароль')
          : (confirm != password ? tr('Пароли не совпадают') : null);
    });

    return _firstNameError == null &&
        _lastNameError == null &&
        _emailError == null &&
        _loginError == null &&
        _passwordError == null &&
        _confirmError == null;
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      await ApiClient.instance.register(
        login: _loginCtrl.text.trim(),
        password: _passwordCtrl.text,
        passwordConfirm: _confirmCtrl.text,
        firstName: _firstNameCtrl.text.trim(),
        lastName: _lastNameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        learningLanguage: _selectedLanguage!,
        ageGroup: _ageGroup!,
        learningGoal: _learningGoals.first,
        learningTopics: _learningGoals,
        referralSource: _referralSource!,
        translationLanguage: _translationLanguage,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError = tr('Не удалось подключиться к серверу. Данные не потеряны — можно попробовать ещё раз.');
      });
    }
  }

  String get _nextLabel => _step == _steps.length - 1 ? tr('Создать аккаунт') : tr('Далее');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _isSubmitting ? null : _goBack,
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.primaryDark),
                  ),
                  Expanded(child: _StepDots(total: _steps.length, current: _step)),
                  const SizedBox(width: 40), // balances the back button so the dots stay centered
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: KeyedSubtree(
                  key: ValueKey(_step),
                  child: _buildStep(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('register-next-button'),
                  onPressed: (_isSubmitting || !_canAdvance) ? null : _goNext,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.rowRadius)),
                  ),
                  child: _isSubmitting
                      ? SkeletonPulse(
                          child: Text(_nextLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        )
                      : Text(_nextLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_stepKey) {
      case 'language':
        return _LanguageStep(
          isLoading: _isLoadingLanguages,
          error: _languagesError,
          languages: _languages,
          selected: _selectedLanguage,
          showAll: _showAllLanguages,
          onRetry: _loadLanguages,
          onSelect: (code) => setState(() => _selectedLanguage = code),
          onShowAll: () => setState(() => _showAllLanguages = true),
        );
      case 'translation':
        return _ChoiceStep(
          title: tr('На каком языке показывать перевод слов?'),
          subtitle: tr('Это можно изменить в настройках.'),
          keyPrefix: 'translation',
          options: const [(code: 'tg', label: 'Тоҷикӣ'), (code: 'uz', label: 'Oʻzbekcha')],
          selected: _translationLanguage,
          onSelect: (code) => setState(() => _translationLanguage = code),
        );
      case 'account':
        return _AccountStep(
          firstNameCtrl: _firstNameCtrl,
          lastNameCtrl: _lastNameCtrl,
          emailCtrl: _emailCtrl,
          loginCtrl: _loginCtrl,
          passwordCtrl: _passwordCtrl,
          confirmCtrl: _confirmCtrl,
          firstNameError: _firstNameError,
          lastNameError: _lastNameError,
          emailError: _emailError,
          loginError: _loginError,
          passwordError: _passwordError,
          confirmError: _confirmError,
          onChanged: () => setState(() {}),
        );
      case 'age':
        return _ChoiceStep(
          title: tr('Укажите ваш возраст'),
          keyPrefix: 'age',
          options: _ageGroups,
          selected: _ageGroup,
          onSelect: (code) => setState(() => _ageGroup = code),
        );
      case 'goal':
        return _ChoiceStep(
          title: tr('Для чего вы изучаете язык?'),
          subtitle: tr('Можно выбрать несколько'),
          keyPrefix: 'goal',
          options: learningGoals,
          selectedMany: _learningGoals,
          onSelect: (code) => setState(
            () => _learningGoals.contains(code) ? _learningGoals.remove(code) : _learningGoals.add(code),
          ),
        );
      case 'referral':
        return _ChoiceStep(
          title: tr('Как вы нас нашли?'),
          keyPrefix: 'referral',
          options: _referralSources,
          selected: _referralSource,
          onSelect: (code) => setState(() => _referralSource = code),
          footer: _submitError == null
              ? null
              : _ErrorBanner(message: _submitError!),
        );
    }
    return const SizedBox.shrink();
  }
}

/// The compact "where am I" indicator -- a pill that grows for the active
/// step, a plain dot for the rest, all from existing tokens (no new
/// shape or color).
class _StepDots extends StatelessWidget {
  final int total;
  final int current;
  const _StepDots({required this.total, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final active = i <= current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: i == current ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? AppColors.primary : AppColors.progressTrack,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

class _StepScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? footer;

  const _StepScaffold({required this.title, this.subtitle, required this.child, this.footer});

  @override
  Widget build(BuildContext context) {
    // A plain Column in a SingleChildScrollView, not a ListView -- this
    // step's content is always a short, fixed set of fields/choices
    // (never a long virtualized list), and a ListView's sliver only
    // realizes children near the current viewport, which silently drops
    // the title out of the element tree once error text pushes the
    // account step taller than the window (found the hard way: an
    // integration test's own find.text('Данные аккаунта') came back
    // empty right after a failed validation, even though _step hadn't
    // moved at all).
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: const TextStyle(fontSize: 13.5, color: AppColors.secondaryText)),
          ],
          const SizedBox(height: 20),
          child,
          if (footer != null) ...[const SizedBox(height: 16), footer!],
        ],
      ),
    );
  }
}

class _LanguageStep extends StatelessWidget {
  final bool isLoading;
  final String? error;
  final List<GuyoDictionary> languages;
  final String? selected;
  final bool showAll;
  final VoidCallback onRetry;
  final ValueChanged<String> onSelect;
  final VoidCallback onShowAll;

  const _LanguageStep({
    required this.isLoading,
    required this.error,
    required this.languages,
    required this.selected,
    required this.showAll,
    required this.onRetry,
    required this.onSelect,
    required this.onShowAll,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SkeletonList(avatar: false, rows: 4);
    }
    if (error != null) {
      return _StepScaffold(
        title: tr('Какой язык хотите изучать?'),
        child: GuyoCard(
          child: Column(
            children: [
              Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.secondaryText)),
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: Text(tr('Повторить'))),
            ],
          ),
        ),
      );
    }
    if (languages.isEmpty) {
      return _StepScaffold(
        title: tr('Какой язык хотите изучать?'),
        child: GuyoCard(
          child: Text(
            tr('Пока нет доступных языков для изучения. Загляните чуть позже.'),
            style: TextStyle(color: AppColors.secondaryText),
          ),
        ),
      );
    }

    final visible = (showAll || languages.length <= 4) ? languages : languages.sublist(0, 4);
    final showMoreButton = !showAll && languages.length > 4;

    return _StepScaffold(
      title: tr('Какой язык хотите изучать?'),
      subtitle: tr('Это будет ваш основной язык обучения в GuYo.'),
      child: Column(
        children: [
          for (final dict in visible) ...[
            SelectableCard(
              key: ValueKey('register-language-${dict.language}'),
              label: dict.languageLabel,
              selected: selected == dict.language,
              onTap: () => onSelect(dict.language),
            ),
            const SizedBox(height: 10),
          ],
          if (showMoreButton)
            TextButton(
              key: const ValueKey('register-show-all-languages'),
              onPressed: onShowAll,
              child: Text(tr('Другие доступные языки'), style: TextStyle(fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}

class _AccountStep extends StatelessWidget {
  final TextEditingController firstNameCtrl;
  final TextEditingController lastNameCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController loginCtrl;
  final TextEditingController passwordCtrl;
  final TextEditingController confirmCtrl;
  final String? firstNameError;
  final String? lastNameError;
  final String? emailError;
  final String? loginError;
  final String? passwordError;
  final String? confirmError;
  final VoidCallback onChanged;

  const _AccountStep({
    required this.firstNameCtrl,
    required this.lastNameCtrl,
    required this.emailCtrl,
    required this.loginCtrl,
    required this.passwordCtrl,
    required this.confirmCtrl,
    required this.firstNameError,
    required this.lastNameError,
    required this.emailError,
    required this.loginError,
    required this.passwordError,
    required this.confirmError,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: tr('Данные аккаунта'),
      child: Column(
        children: [
          _FormField(
            fieldKey: const ValueKey('register-field-first-name'),
            label: tr('Имя'),
            controller: firstNameCtrl,
            error: firstNameError,
            onChanged: onChanged,
          ),
          const SizedBox(height: 12),
          _FormField(
            fieldKey: const ValueKey('register-field-last-name'),
            label: tr('Фамилия'),
            controller: lastNameCtrl,
            error: lastNameError,
            onChanged: onChanged,
          ),
          const SizedBox(height: 12),
          _FormField(
            fieldKey: const ValueKey('register-field-email'),
            label: 'Email',
            controller: emailCtrl,
            error: emailError,
            onChanged: onChanged,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          _FormField(
            fieldKey: const ValueKey('register-field-login'),
            label: tr('Логин'),
            controller: loginCtrl,
            error: loginError,
            onChanged: onChanged,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          _FormField(
            fieldKey: const ValueKey('register-field-password'),
            label: tr('Пароль'),
            controller: passwordCtrl,
            error: passwordError,
            onChanged: onChanged,
            obscure: true,
          ),
          const SizedBox(height: 12),
          _FormField(
            fieldKey: const ValueKey('register-field-confirm'),
            label: tr('Подтверждение пароля'),
            controller: confirmCtrl,
            error: confirmError,
            onChanged: onChanged,
            obscure: true,
          ),
        ],
      ),
    );
  }
}

/// One GuYo-styled input: the same violet fill + no visible outline +
/// rowRadius corners already used elsewhere (see PromoScreen's own code
/// field) -- error text sits directly under the field, small and plain,
/// never a giant banner.
class _FormField extends StatelessWidget {
  final Key? fieldKey;
  final String label;
  final TextEditingController controller;
  final String? error;
  final VoidCallback onChanged;
  final bool obscure;
  final bool autocorrect;
  final TextInputType? keyboardType;

  const _FormField({
    this.fieldKey,
    required this.label,
    required this.controller,
    required this.error,
    required this.onChanged,
    this.obscure = false,
    this.autocorrect = true,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
        const SizedBox(height: 6),
        TextField(
          key: fieldKey,
          controller: controller,
          obscureText: obscure,
          autocorrect: autocorrect,
          enableSuggestions: autocorrect,
          keyboardType: keyboardType,
          onChanged: (_) => onChanged(),
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
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(error!, style: const TextStyle(fontSize: 12, color: AppColors.danger, fontWeight: FontWeight.w600)),
        ],
      ],
    );
  }
}

/// One question, one list of mutually-exclusive answers -- shared shape
/// for age/goal/referral (and reused by the language step for its own
/// selection cards below).
class _ChoiceStep extends StatelessWidget {
  final String title;
  final String keyPrefix;
  final List<({String code, String label})> options;
  final String? selected;
  final List<String>? selectedMany;
  final String? subtitle;
  final ValueChanged<String> onSelect;
  final Widget? footer;

  const _ChoiceStep({
    required this.title,
    required this.keyPrefix,
    required this.options,
    this.selected,
    this.selectedMany,
    this.subtitle,
    required this.onSelect,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: title,
      footer: footer,
      child: Column(
        children: [
          if (subtitle != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(subtitle!, style: const TextStyle(fontSize: 14, color: AppColors.secondaryText)),
            ),
            const SizedBox(height: 12),
          ],
          for (final option in options) ...[
            SelectableCard(
              key: ValueKey('register-$keyPrefix-${option.code}'),
              label: option.label,
              selected: selectedMany?.contains(option.code) ?? selected == option.code,
              onTap: () => onSelect(option.code),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.dangerLight,
        borderRadius: BorderRadius.circular(AppShapes.rowRadius),
      ),
      child: Text(message, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
    );
  }
}
