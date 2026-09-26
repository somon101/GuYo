import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/dictionary.dart';
import '../theme/app_colors.dart';
import '../widgets/guyo_ui.dart';
import 'home_screen.dart';

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

const int _totalSteps = 5;

const List<({String code, String label})> _ageGroups = [
  (code: '12-17', label: '12–17 лет'),
  (code: '18-24', label: '18–24 года'),
  (code: '25+', label: '25+ лет'),
];

const List<({String code, String label})> _learningGoals = [
  (code: 'study', label: 'Для учёбы'),
  (code: 'work', label: 'Для работы'),
  (code: 'communication', label: 'Для общения'),
  (code: 'travel', label: 'Для путешествий'),
  (code: 'relocation', label: 'Для переезда'),
  (code: 'personal', label: 'Для себя'),
  (code: 'other', label: 'Другое'),
];

const List<({String code, String label})> _referralSources = [
  (code: 'social', label: 'Социальные сети'),
  (code: 'youtube', label: 'YouTube'),
  (code: 'telegram', label: 'Telegram'),
  (code: 'search', label: 'Поисковик'),
  (code: 'friends', label: 'От друзей или знакомых'),
  (code: 'ads', label: 'Реклама'),
  (code: 'other', label: 'Другое'),
];

class _RegisterScreenState extends State<RegisterScreen> {
  int _step = 0;

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
  String? _learningGoal;
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
        _languagesError = 'Не удалось загрузить список языков. Проверьте интернет.';
      });
    }
  }

  bool get _canAdvance {
    switch (_step) {
      case 0:
        return _selectedLanguage != null;
      case 1:
        return true; // this step validates its own fields on Next
      case 2:
        return _ageGroup != null;
      case 3:
        return _learningGoal != null;
      case 4:
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
    if (_step == 1 && !_validateAccountStep()) {
      return;
    }
    if (_step < _totalSteps - 1) {
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
      _firstNameError = firstName.isEmpty ? 'Введите имя' : null;
      _lastNameError = lastName.isEmpty ? 'Введите фамилию' : null;
      _emailError = email.isEmpty
          ? 'Введите email'
          : (!emailLooksValid ? 'Некорректный email' : null);
      _loginError = login.isEmpty
          ? 'Введите логин'
          : (login.length < 3 ? 'Минимум 3 символа' : null);
      _passwordError = password.isEmpty
          ? 'Введите пароль'
          : (password.length < 4 ? 'Минимум 4 символа' : null);
      _confirmError = confirm.isEmpty
          ? 'Повторите пароль'
          : (confirm != password ? 'Пароли не совпадают' : null);
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
        learningGoal: _learningGoal!,
        referralSource: _referralSource!,
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
        _submitError = 'Не удалось подключиться к серверу. Данные не потеряны — можно попробовать ещё раз.';
      });
    }
  }

  String get _nextLabel => _step == _totalSteps - 1 ? 'Создать аккаунт' : 'Далее';

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
                  Expanded(child: _StepDots(total: _totalSteps, current: _step)),
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
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
    switch (_step) {
      case 0:
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
      case 1:
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
      case 2:
        return _ChoiceStep(
          title: 'Укажите ваш возраст',
          keyPrefix: 'age',
          options: _ageGroups,
          selected: _ageGroup,
          onSelect: (code) => setState(() => _ageGroup = code),
        );
      case 3:
        return _ChoiceStep(
          title: 'Для чего вы изучаете язык?',
          keyPrefix: 'goal',
          options: _learningGoals,
          selected: _learningGoal,
          onSelect: (code) => setState(() => _learningGoal = code),
        );
      case 4:
        return _ChoiceStep(
          title: 'Как вы нас нашли?',
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
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return _StepScaffold(
        title: 'Какой язык хотите изучать?',
        child: GuyoCard(
          child: Column(
            children: [
              Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.secondaryText)),
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: const Text('Повторить')),
            ],
          ),
        ),
      );
    }
    if (languages.isEmpty) {
      return _StepScaffold(
        title: 'Какой язык хотите изучать?',
        child: const GuyoCard(
          child: Text(
            'Пока нет доступных языков для изучения. Загляните чуть позже.',
            style: TextStyle(color: AppColors.secondaryText),
          ),
        ),
      );
    }

    final visible = (showAll || languages.length <= 4) ? languages : languages.sublist(0, 4);
    final showMoreButton = !showAll && languages.length > 4;

    return _StepScaffold(
      title: 'Какой язык хотите изучать?',
      subtitle: 'Это будет ваш основной язык обучения в GuYo.',
      child: Column(
        children: [
          for (final dict in visible) ...[
            _ChoiceTile(
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
              child: const Text('Другие доступные языки', style: TextStyle(fontWeight: FontWeight.w700)),
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
      title: 'Данные аккаунта',
      child: Column(
        children: [
          _FormField(
            fieldKey: const ValueKey('register-field-first-name'),
            label: 'Имя',
            controller: firstNameCtrl,
            error: firstNameError,
            onChanged: onChanged,
          ),
          const SizedBox(height: 12),
          _FormField(
            fieldKey: const ValueKey('register-field-last-name'),
            label: 'Фамилия',
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
            label: 'Логин',
            controller: loginCtrl,
            error: loginError,
            onChanged: onChanged,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          _FormField(
            fieldKey: const ValueKey('register-field-password'),
            label: 'Пароль',
            controller: passwordCtrl,
            error: passwordError,
            onChanged: onChanged,
            obscure: true,
          ),
          const SizedBox(height: 12),
          _FormField(
            fieldKey: const ValueKey('register-field-confirm'),
            label: 'Подтверждение пароля',
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
  final ValueChanged<String> onSelect;
  final Widget? footer;

  const _ChoiceStep({
    required this.title,
    required this.keyPrefix,
    required this.options,
    required this.selected,
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
          for (final option in options) ...[
            _ChoiceTile(
              key: ValueKey('register-$keyPrefix-${option.code}'),
              label: option.label,
              selected: selected == option.code,
              onTap: () => onSelect(option.code),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

/// One selectable card: a hairline border that turns into GuYo's primary
/// indigo, plus a filled check, when chosen -- the one new visual piece
/// this screen needed, built purely from AppColors/AppShapes.
class _ChoiceTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceTile({super.key, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.violetSurface : Colors.white,
      borderRadius: BorderRadius.circular(AppShapes.rowRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppShapes.rowRadius),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppShapes.rowRadius),
            border: Border.all(color: selected ? AppColors.primary : AppColors.cardBorder, width: selected ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
                ),
              ),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: selected ? AppColors.primary : AppColors.muted,
                size: 22,
              ),
            ],
          ),
        ),
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
