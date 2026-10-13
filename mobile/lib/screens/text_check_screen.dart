import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/text_check.dart';
import '../services/text_check_settings.dart';
import '../theme/app_colors.dart';

/// «Проверка текста»: paste the Russian message you are about to send, pick
/// who it is for, and get the mistakes, the explanations and the corrected
/// text back.
///
/// Built to the approved prototype, one state at a time:
/// - the top bar's three pills are this screen's ONLY settings -- formality,
///   the language explanations come in, and whether punctuation is checked;
/// - the intro and the empty state disappear after the first message;
/// - the history is deliberately NOT kept: every send wipes the screen and
///   shows exactly one message and its answer;
/// - the addressee resets after every send (the writer's own gender, the
///   formality, the language and the punctuation do not -- they are saved on
///   the device, see [TextCheckSettings]).
///
/// Nothing here changes anything else in the app: the interface language
/// (l10n.dart's appLanguage) is never touched by this screen, and no score,
/// streak or achievement is involved -- this is a writing aid, not an
/// exercise.
class TextCheckScreen extends StatefulWidget {
  const TextCheckScreen({super.key});

  @override
  State<TextCheckScreen> createState() => _TextCheckScreenState();
}

class _TextCheckScreenState extends State<TextCheckScreen> {
  /// The same limit the backend enforces (app/schemas/text_check.py).
  static const int _maxLength = 500;

  final _controller = TextEditingController();
  final _scroll = ScrollController();

  TextCheckSettings _settings = TextCheckSettings.defaults();

  /// null means «не знаю» -- the addressee is never carried between messages.
  String? _addressee;

  bool _busy = false;

  /// Whether the intro/empty state has been left behind by a first send.
  bool _sent = false;
  String _question = '';
  TextCheckResult? _result;
  String? _errorMessage;
  bool _explanationsOpen = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _loadSettings();
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Only the send button's enabled state depends on the field, so this
  /// rebuilds for the field's own text and nothing else.
  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSettings() async {
    final settings = await TextCheckSettings.load();
    if (!mounted) return;
    setState(() => _settings = settings);
  }

  void _updateSettings(TextCheckSettings next) {
    setState(() => _settings = next);
    next.save();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;

    // The addressee of THIS message, taken before the reset below.
    final addressee = _addressee ?? 'unknown';

    setState(() {
      _busy = true;
      _sent = true;
      _question = text;
      _result = null;
      _errorMessage = null;
      _explanationsOpen = false;
      // Every message is asked afresh: who it is for is never remembered.
      _addressee = null;
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final result = await ApiClient.instance.checkText(
        text: text,
        userGender: _settings.userGender,
        addresseeGender: addressee,
        formality: _settings.formality.isEmpty ? null : _settings.formality,
        checkPunctuation: _settings.checkPunctuation,
        explanationLanguage: _settings.explanationLanguage,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _busy = false;
      });
    } on ApiException catch (e) {
      // The backend's own wording is meant to be shown as-is.
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = tr('Ошибка сети. Проверьте интернет.');
        _busy = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  /// Enter sends, Shift+Enter is a new line -- the prototype's own rule.
  /// (The on-screen keyboard's own Enter still inserts a line break.)
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
    if (_controller.text.trim().isNotEmpty && !_busy) _send();
    return KeyEventResult.handled;
  }

  void _cycleFormality() {
    final next = switch (_settings.formality) {
      '' => 'formal',
      'formal' => 'informal',
      _ => '',
    };
    _updateSettings(_settings.copyWith(formality: next));
  }

  /// The explanation language, as a small sheet -- the same picker shape the
  /// app already uses for statuses (screens/status_picker_sheet.dart).
  Future<void> _pickLanguage() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.canvas,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text(
              tr('Язык объяснений'),
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
            ),
            const SizedBox(height: 8),
            for (final language in textCheckLanguages)
              ListTile(
                title: Text(
                  language.label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: language.code == _settings.explanationLanguage ? FontWeight.w700 : FontWeight.w500,
                    color: language.code == _settings.explanationLanguage
                        ? AppColors.primary
                        : AppColors.primaryDark,
                  ),
                ),
                trailing: language.code == _settings.explanationLanguage
                    ? Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(language.code),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    _updateSettings(_settings.copyWith(explanationLanguage: picked));
  }

  String get _languageLabel =>
      textCheckLanguages.firstWhere((l) => l.code == _settings.explanationLanguage).label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        title: Text(
          tr('Проверка текста'),
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
        ),
        actions: [
          _TopPill(
            label: '🎩',
            tooltip: switch (_settings.formality) {
              'formal' => tr('Формальность: формально'),
              'informal' => tr('Формальность: неформально'),
              _ => tr('Формальность: не выбрано'),
            },
            active: _settings.formality.isNotEmpty,
            activeColor: _settings.formality == 'informal' ? AppColors.warningLight : null,
            activeTextColor: _settings.formality == 'informal' ? AppColors.warning : null,
            onTap: _cycleFormality,
          ),
          const SizedBox(width: 6),
          _TopPill(
            label: textCheckLanguageCode(_settings.explanationLanguage),
            tooltip: tr('Язык объяснений: {0}', [_languageLabel]),
            // Only a language other than the default one is highlighted, so
            // the ordinary Russian case stays quiet in the bar.
            active: _settings.explanationLanguage != 'ru',
            onTap: _pickLanguage,
          ),
          const SizedBox(width: 6),
          _TopPill(
            label: '✏️',
            tooltip: _settings.checkPunctuation ? tr('Проверять пунктуацию: вкл') : tr('Проверять пунктуацию: выкл'),
            active: _settings.checkPunctuation,
            onTap: () => _updateSettings(_settings.copyWith(checkPunctuation: !_settings.checkPunctuation)),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(child: _buildContent()),
            _inputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (!_sent) return _intro();
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        Align(alignment: Alignment.centerRight, child: _userBubble(_question)),
        const SizedBox(height: 16),
        if (_busy) const _TypingCard(),
        if (_errorMessage != null) _errorCard(_errorMessage!),
        if (_result != null) _answerCard(_result!),
      ],
    );
  }

  /// The intro and empty state, shown until the first message is sent.
  Widget _intro() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Проверка текста'),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tr('Проверьте грамматику, стиль и ошибки в вашем сообщении.'),
            style: TextStyle(fontSize: 14, height: 1.45, color: AppColors.secondaryText),
          ),
          const SizedBox(height: 56),
          Center(
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.violetSurface, AppColors.primary.withValues(alpha: 0.18)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.18),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Image.asset('assets/icon/guyo_icon_foreground.png', width: 48, height: 48),
                ),
                const SizedBox(height: 16),
                Text(
                  tr('Напишите сообщение — я проверю его\nи объясню ошибки.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.secondaryText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _userBubble(String text) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.violetSurface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(6),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 15, height: 1.5, color: AppColors.primaryDark),
      ),
    );
  }

  Widget _answerCard(TextCheckResult result) {
    final hasErrors = result.hasErrors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppShapes.cardRadius),
        boxShadow: AppShapes.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statusChip(result),
          if (result.summary.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              result.summary,
              style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.secondaryText),
            ),
          ],
          if (hasErrors) ...[
            const SizedBox(height: 12),
            for (var i = 0; i < result.errors.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _errorBox(result.errors[i]),
            ],
            const SizedBox(height: 12),
            _explainToggle(),
          ],
          // The corrected text is only worth showing when something was
          // actually corrected -- exactly as in the prototype.
          if (hasErrors && result.correctedText.isNotEmpty) ...[
            const SizedBox(height: 12),
            _correctedBox(result.correctedText),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(TextCheckResult result) {
    final String label;
    final IconData icon;
    final Color color;
    final Color background;
    if (result.ok && !result.hasErrors) {
      label = tr('Всё правильно');
      icon = Icons.check_rounded;
      color = AppColors.success;
      background = AppColors.successLight;
    } else if (result.ok) {
      label = tr('Проверка');
      icon = Icons.auto_awesome_rounded;
      color = AppColors.primary;
      background = AppColors.violetSurface;
    } else {
      label = tr('Есть ошибки');
      icon = Icons.priority_high_rounded;
      color = AppColors.danger;
      background = AppColors.dangerLight;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppShapes.pillRadius)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _errorBox(TextCheckError error) {
    final isStyle = textCheckGroupIsStyle(error.group);
    final accent = isStyle ? AppColors.warning : AppColors.danger;
    final accentLight = isStyle ? AppColors.warningLight : AppColors.dangerLight;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: accentLight, shape: BoxShape.circle),
                child: Text(
                  textCheckGroupGlyph(error.group),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: accent),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  textCheckGroupTitle(error.group, _settings.explanationLanguage).toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: AppColors.secondaryText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text.rich(_mistakeSpan(error), style: const TextStyle(fontSize: 15, height: 1.4)),
          if (_explanationsOpen && error.explanation.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.cardBorder)),
              ),
              child: Text(
                error.explanation,
                style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.secondaryText),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// "прит → привет": the wrong fragment struck through in red, then what it
  /// should be in green. A one-sided entry (the model may send only one of
  /// the two) is shown on its own rather than next to a dangling arrow.
  TextSpan _mistakeSpan(TextCheckError error) {
    // Deliberately not const: every AppColors value is a getter that follows
    // the current theme, so it can never be a compile-time constant.
    final strike = TextStyle(
      color: AppColors.danger,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.lineThrough,
      decorationThickness: 2,
    );
    final arrow = TextStyle(color: AppColors.secondaryText, fontWeight: FontWeight.w500);
    final good = TextStyle(color: AppColors.success, fontWeight: FontWeight.w700);
    final hasFragment = error.fragment.isNotEmpty;
    final hasCorrect = error.correct.isNotEmpty;
    return TextSpan(
      children: [
        if (hasFragment) TextSpan(text: error.fragment, style: strike),
        if (hasFragment && hasCorrect) TextSpan(text: '  →  ', style: arrow),
        if (hasCorrect) TextSpan(text: error.correct, style: good),
      ],
    );
  }

  Widget _explainToggle() {
    return SizedBox(
      width: double.infinity,
      height: 42,
      child: TextButton(
        onPressed: () {
          setState(() => _explanationsOpen = !_explanationsOpen);
          _scrollToBottom();
        },
        style: TextButton.styleFrom(
          backgroundColor: AppColors.violetSurface,
          foregroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.pillRadius)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedRotation(
              turns: _explanationsOpen ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(Icons.expand_more_rounded, size: 18),
            ),
            const SizedBox(width: 6),
            Text(
              _explanationsOpen ? tr('Скрыть объяснение') : tr('Показать объяснение'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _correctedBox(String corrected) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.successLight, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, size: 13, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('Исправленный текст').toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: AppColors.success,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            corrected,
            style: TextStyle(fontSize: 15, height: 1.5, color: AppColors.primaryDark),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppShapes.cardRadius),
        boxShadow: AppShapes.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.dangerLight,
              borderRadius: BorderRadius.circular(AppShapes.pillRadius),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, size: 14, color: AppColors.danger),
                const SizedBox(width: 6),
                Text(
                  tr('Ошибка'),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.danger),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: TextStyle(fontSize: 14, height: 1.45, color: AppColors.secondaryText),
          ),
        ],
      ),
    );
  }

  Widget _inputBar() {
    final canSend = _controller.text.trim().isNotEmpty && !_busy;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(26),
        boxShadow: AppShapes.cardShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Focus(
                  onKeyEvent: _onKey,
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 3,
                    maxLength: _maxLength,
                    textCapitalization: TextCapitalization.sentences,
                    cursorColor: AppColors.primary,
                    style: TextStyle(fontSize: 15, height: 1.4, color: AppColors.primaryDark),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      counterText: '',
                      hintText: tr('Введите текст...'),
                      hintStyle: TextStyle(fontSize: 15, color: AppColors.muted),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // Horizontally scrollable, like the prototype's own chips
                // row: a long translation of "К мужчине" must never push the
                // send button off the card.
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _addresseeChip('male', '👨', tr('К мужчине')),
                      const SizedBox(width: 6),
                      _addresseeChip('female', '👩', tr('К женщине')),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _genderToggle(),
              const SizedBox(height: 6),
              _sendButton(canSend),
            ],
          ),
        ],
      ),
    );
  }

  /// «К мужчине» / «К женщине»: tapping the chosen one again clears it, so
  /// "not chosen" is a state the user can always get back to.
  Widget _addresseeChip(String value, String glyph, String label) {
    final active = _addressee == value;
    return Material(
      color: active ? AppColors.violetSurface : AppColors.softFill,
      borderRadius: BorderRadius.circular(AppShapes.pillRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppShapes.pillRadius),
        onTap: () => setState(() => _addressee = active ? null : value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            '$glyph $label',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: active ? AppColors.primary : AppColors.secondaryText,
            ),
          ),
        ),
      ),
    );
  }

  Widget _genderToggle() {
    final female = _settings.userGender == 'female';
    return Tooltip(
      message: female ? tr('Я — женщина') : tr('Я — мужчина'),
      child: Material(
        color: female ? AppColors.tile(const Color(0xFFFFE4EE)) : AppColors.violetSurface,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _updateSettings(_settings.copyWith(userGender: female ? 'male' : 'female')),
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            child: Text(female ? '👩' : '👨', style: const TextStyle(fontSize: 15)),
          ),
        ),
      ),
    );
  }

  Widget _sendButton(bool canSend) {
    return GestureDetector(
      onTap: canSend ? _send : null,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: canSend ? AppColors.primary : AppColors.progressTrack,
          boxShadow: canSend
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Icon(
          Icons.send_rounded,
          size: 18,
          color: canSend ? Colors.white : AppColors.muted,
        ),
      ),
    );
  }
}

/// One of the three round pills in the top bar: quiet on the surface by
/// default, tinted when its setting is on.
class _TopPill extends StatelessWidget {
  final String label;
  final String tooltip;
  final bool active;
  final Color? activeColor;
  final Color? activeTextColor;
  final VoidCallback onTap;

  const _TopPill({
    required this.label,
    required this.tooltip,
    required this.active,
    required this.onTap,
    this.activeColor,
    this.activeTextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 40,
        height: 32,
        decoration: BoxDecoration(
          color: active ? (activeColor ?? AppColors.violetSurface) : AppColors.surface,
          borderRadius: BorderRadius.circular(AppShapes.pillRadius),
          boxShadow: AppShapes.cardShadow,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppShapes.pillRadius),
            onTap: onTap,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  color: active ? (activeTextColor ?? AppColors.primary) : AppColors.secondaryText,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The three dots while the check is on its way -- the prototype's own
/// waiting state, as a card in the same place the answer will appear.
class _TypingCard extends StatefulWidget {
  const _TypingCard();

  @override
  State<_TypingCard> createState() => _TypingCardState();
}

class _TypingCardState extends State<_TypingCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// One dot's opacity through its blink: low, up to full at 30% of the
  /// cycle, back down, then a rest.
  double _opacity(double phase) {
    final t = phase % 1.0;
    if (t < 0.3) return 0.3 + 0.7 * (t / 0.3);
    if (t < 0.6) return 1.0 - 0.7 * ((t - 0.3) / 0.3);
    return 0.3;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppShapes.cardRadius),
        boxShadow: AppShapes.cardShadow,
      ),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => Opacity(
                  opacity: _opacity(_controller.value + i * 0.2),
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: AppColors.muted, shape: BoxShape.circle),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
