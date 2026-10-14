import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/text_check.dart';
import '../services/text_check_settings.dart';
import '../theme/app_colors.dart';
import '../widgets/guyo_ui.dart';
import '../widgets/in_app_banner.dart';

/// «Проверка текста»: paste the Russian message you are about to send, pick
/// who it is for, and get the mistakes, the explanations and the corrected
/// text back.
///
/// Built to the approved prototype, one state at a time:
/// - the top bar is the app's own bar (the same "GuYo" wordmark as Главная),
///   with this screen's three settings beside it: formality, the language the
///   explanations come in, and whether punctuation is checked;
/// - every setting change is answered by the app's floating notice sliding down
///   from the TOP -- the same one «Текст скопирован» uses -- so the user sees
///   what they just turned on, and what the checker will now assume;
/// - the intro and the empty state disappear after the first message;
/// - the history is deliberately NOT kept: every send wipes the screen and
///   shows exactly one message and its answer;
/// - the addressee resets after every send (the writer's own gender, the
///   formality, the language and the punctuation do not -- they are kept on
///   the device, see [TextCheckSettings]);
/// - how many checks are left today is always on screen, and a repeated text
///   is answered from the backend's cache: instantly, without spending one.
///
/// Nothing here changes anything else in the app: the interface language
/// (l10n.dart's appLanguage) is never touched, and no score, streak or
/// achievement is involved -- this is a writing aid, not an exercise.
class TextCheckScreen extends StatefulWidget {
  const TextCheckScreen({super.key});

  @override
  State<TextCheckScreen> createState() => _TextCheckScreenState();
}

class _TextCheckScreenState extends State<TextCheckScreen> {
  /// Used until the backend says otherwise -- the real limit is the admin's
  /// own `max_chars` (Admin Web -> «ИИ» -> «Проверка текста»).
  static const int _fallbackMaxChars = 500;

  final _controller = TextEditingController();
  final _scroll = ScrollController();

  TextCheckSettings _settings = TextCheckSettings.defaults();

  /// Whether the checker is on, how long a message may be, and what is left
  /// today -- refreshed from every check's own answer, so the counter can
  /// never drift.
  TextCheckInfo? _info;

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
    _loadInfo();
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

  Future<void> _loadInfo() async {
    try {
      final info = await ApiClient.instance.fetchTextCheckInfo();
      if (!mounted) return;
      setState(() => _info = info);
    } catch (_) {
      // Without it the screen still works on the app's own defaults: the
      // backend enforces the real limit anyway and its message is shown.
    }
  }

  /// Saves a setting and acknowledges the tap.
  ///
  /// The acknowledgement is the app's own floating notice sliding down from the
  /// TOP -- the very same one «Текст скопирован» uses, so every tap on this
  /// screen is answered by the same thing in the same place.
  void _updateSettings(TextCheckSettings next, String confirmation) {
    setState(() => _settings = next);
    next.save();
    _confirm(confirmation);
  }

  void _confirm(String message) {
    InAppBanner.show(
      body: message,
      visibleFor: InAppBanner.confirmationVisibleFor,
      // Nothing to open: this only acknowledges what the user just did.
      opensInbox: false,
    );
  }

  int get _maxChars => _info?.maxChars ?? _fallbackMaxChars;

  bool get _checkerDisabled => _info != null && !_info!.enabled;

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy || _checkerDisabled) return;

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
        _info = _info?.afterCheck(result);
      });
    } on ApiException catch (e) {
      // The backend's own wording is meant to be shown as-is -- including
      // "the daily limit is used up", which is the message that matters most
      // on this screen.
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

  /// Formality is ONE switch, not a three-way choice: on means "check that the
  /// message stays formal (Вы)", off means "do not comment on ты/Вы at all".
  void _toggleFormality() {
    final on = _settings.formality == 'formal';
    _updateSettings(
      _settings.copyWith(formality: on ? '' : 'formal'),
      on ? tr('Формальность не проверяю') : tr('Проверяю формальность (Вы)'),
    );
  }

  void _togglePunctuation() {
    final on = !_settings.checkPunctuation;
    _updateSettings(
      _settings.copyWith(checkPunctuation: on),
      on ? tr('Проверяю пунктуацию') : tr('Пунктуацию не проверяю'),
    );
  }

  void _pickLanguage(String code) {
    final label = textCheckLanguages.firstWhere((l) => l.code == code).label;
    _updateSettings(
      _settings.copyWith(explanationLanguage: code),
      tr('Объяснения: {0}', [label]),
    );
  }

  void _toggleUserGender() {
    final female = _settings.userGender == 'female';
    _updateSettings(
      _settings.copyWith(userGender: female ? 'male' : 'female'),
      female ? tr('Учту: ты пишешь как мужчина') : tr('Учту: ты пишешь как женщина'),
    );
  }

  /// «К мужчине» / «К женщине»: tapping the chosen one again clears it, so
  /// "not chosen" is a state the user can always get back to.
  void _chooseAddressee(String value) {
    final wasActive = _addressee == value;
    setState(() => _addressee = wasActive ? null : value);
    _confirm(
      wasActive
          ? tr('Обращение не указано')
          : (value == 'female' ? tr('Учту: обращение к женщине') : tr('Учту: обращение к мужчине')),
    );
  }

  Future<void> _copyCorrected(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    // Purely on screen: nothing is written to the notifications inbox.
    _confirm(tr('Текст скопирован'));
  }

  @override
  Widget build(BuildContext context) {
    final formality = _settings.formality;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        // The app's own mark, not the screen's name: the name lives in the
        // intro below (and disappears with it after the first message, exactly
        // as in the prototype). It shrinks a little when the bar is tight
        // instead of being clipped.
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: GuyoWordmark(fontSize: 24),
        ),
        actions: [
          _TopPill(
            label: '🎩',
            tooltip: formality == 'formal' ? tr('Формальность: проверяю (Вы)') : tr('Формальность: не проверяю'),
            active: formality == 'formal',
            onTap: _toggleFormality,
          ),
          const SizedBox(width: 4),
          _LanguagePill(selected: _settings.explanationLanguage, onSelected: _pickLanguage),
          const SizedBox(width: 4),
          _TopPill(
            label: '✏️',
            tooltip: _settings.checkPunctuation ? tr('Проверять пунктуацию: вкл') : tr('Проверять пунктуацию: выкл'),
            active: _settings.checkPunctuation,
            onTap: _togglePunctuation,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(child: _buildContent()),
            _remainingLine(),
            _inputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_checkerDisabled) return _disabledNotice();
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

  /// Shown instead of everything else when the admin switched the checker off.
  Widget _disabledNotice() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded, size: 44, color: AppColors.muted),
            const SizedBox(height: 16),
            Text(
              tr('Проверка текста сейчас недоступна'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
            ),
            const SizedBox(height: 8),
            Text(
              tr('Загляните позже.'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.secondaryText),
            ),
          ],
        ),
      ),
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
          const SizedBox(height: 40),
          Center(
            child: Column(
              children: [
                // The app's own mark, plainly -- no frame, no plate, no
                // gradient behind it: this is GuYo's feature, not some
                // third-party "AI" badge.
                // The app's own logo, WHOLE -- the mark and the wordmark, on a
                // transparent background and cropped so it sits centred.
                //
                // The light theme has no plate under it, as asked: it sits
                // straight on the canvas. The dark theme is the one exception --
                // the wordmark is a very dark navy that would vanish against the
                // dark canvas, so there it gets a plain white plate to stay
                // readable.
                Container(
                  padding: AppColors.dark ? const EdgeInsets.symmetric(horizontal: 20, vertical: 16) : EdgeInsets.zero,
                  decoration: AppColors.dark
                      ? BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: AppShapes.cardShadow,
                        )
                      : null,
                  child: Image.asset('assets/icon/guyo_logo_full.png', height: 150),
                ),
                const SizedBox(height: 14),
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

  Widget _remainingLine() {
    final info = _info;
    if (info == null || !info.enabled) return const SizedBox.shrink();
    final noLimit = info.unlimited || info.dailyLimit == null;
    final left = info.remaining ?? 0;
    final exhausted = !noLimit && left <= 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: Text(
        noLimit
            ? tr('Проверок текста: без ограничений')
            : exhausted
                ? tr('Проверки на сегодня закончились')
                : tr('Осталось проверок сегодня: {0} из {1}', [left, info.dailyLimit]),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          fontWeight: exhausted ? FontWeight.w700 : FontWeight.w500,
          color: exhausted ? AppColors.warning : AppColors.secondaryText,
        ),
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
          Row(
            children: [
              _statusChip(result),
              // The answer came from the cache: nothing was spent and the limit
              // did not move -- saying so is what makes that legible.
              if (result.cached) ...[
                const SizedBox(width: 8),
                Text(
                  tr('готовый ответ'),
                  style: TextStyle(fontSize: 11.5, color: AppColors.secondaryText),
                ),
              ],
            ],
          ),
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
  /// should be in green. A one-sided entry (the model may send only one of the
  /// two) is shown on its own rather than next to a dangling arrow.
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
              // Copy: the icon is the discoverable way, and tapping the text
              // itself works too (both do exactly the same thing).
              IconButton(
                key: const ValueKey('text-check-copy'),
                onPressed: () => _copyCorrected(corrected),
                tooltip: tr('Скопировать'),
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                color: AppColors.success,
                icon: const Icon(Icons.copy_rounded),
              ),
            ],
          ),
          const SizedBox(height: 2),
          GestureDetector(
            onTap: () => _copyCorrected(corrected),
            behavior: HitTestBehavior.opaque,
            child: Text(
              corrected,
              style: TextStyle(fontSize: 15, height: 1.5, color: AppColors.primaryDark),
            ),
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
    final canSend = _controller.text.trim().isNotEmpty && !_busy && !_checkerDisabled;
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
                    enabled: !_checkerDisabled,
                    minLines: 1,
                    maxLines: 3,
                    maxLength: _maxChars,
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
                // Horizontally scrollable, like the prototype's own chips row:
                // a long translation of "К мужчине" must never push the send
                // button off the card.
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

  Widget _addresseeChip(String value, String glyph, String label) {
    final active = _addressee == value;
    // ON is a FILLED indigo pill with a check inside it, OFF is a quiet grey
    // one: a pale tint was too easy to miss, and "did my tap register?" is
    // exactly the question this row must answer at a glance.
    return Material(
      color: active ? AppColors.primary : AppColors.softFill,
      borderRadius: BorderRadius.circular(AppShapes.pillRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppShapes.pillRadius),
        onTap: () => _chooseAddressee(value),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (active) ...[
                const Icon(Icons.check_rounded, size: 15, color: Colors.white),
                const SizedBox(width: 4),
              ],
              Text(
                '$glyph $label',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : AppColors.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _genderToggle() {
    final female = _settings.userGender == 'female';
    // A ring in the chosen gender's own colour: the circle is always "one of
    // the two", so the ring is what makes the current choice read as chosen.
    final accent = female ? const Color(0xFFE85A94) : AppColors.primary;
    return Tooltip(
      message: female ? tr('Я — женщина') : tr('Я — мужчина'),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: accent, width: 2),
        ),
        child: Material(
          color: female ? AppColors.tile(const Color(0xFFFFE4EE)) : AppColors.violetSurface,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _toggleUserGender,
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              child: Text(female ? '👩' : '👨', style: const TextStyle(fontSize: 15)),
            ),
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

/// One of the two round pills beside the language picker: quiet on the surface
/// by default, tinted when its setting is on. The same shape on both sides of
/// the language pill, so the bar reads as one row.
class _TopPill extends StatelessWidget {
  final String label;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;

  const _TopPill({
    required this.label,
    required this.tooltip,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 36,
        height: 32,
        decoration: BoxDecoration(
          color: active ? AppColors.violetSurface : AppColors.softFill,
          borderRadius: BorderRadius.circular(AppShapes.pillRadius),
          // ON is a violet pill with a solid indigo rim, OFF is a dimmed grey
          // one: "did my tap turn it on?" must never be a question the bar
          // leaves open, and the emoji inside stays readable either way.
          border: active ? Border.all(color: AppColors.primary, width: 1.5) : null,
          boxShadow: active ? AppShapes.cardShadow : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppShapes.pillRadius),
            onTap: onTap,
            child: Center(
              child: Opacity(
                opacity: active ? 1 : 0.45,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    color: active ? AppColors.primary : AppColors.secondaryText,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The explanation language, as a button + menu pair copied from the learning
/// language switcher on Главная (same pill, same menu, same check on the
/// current row) -- one visual language for "pick a language" in the app.
///
/// Purely local: what THIS screen shows its explanations in. The app's own
/// interface language is never touched.
class _LanguagePill extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;

  const _LanguagePill({required this.selected, required this.onSelected});

  Widget _badge(String code, {bool isCurrent = true}) {
    return Container(
      width: 26,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isCurrent ? AppColors.primary : AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        textCheckLanguageCode(code),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: isCurrent ? Colors.white : AppColors.primary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = textCheckLanguages.firstWhere((l) => l.code == selected);
    return PopupMenuButton<String>(
      key: const ValueKey('text-check-language'),
      tooltip: tr('Язык объяснений'),
      onSelected: onSelected,
      offset: const Offset(0, 40),
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (context) => [
        for (final language in textCheckLanguages)
          PopupMenuItem(
            value: language.code,
            height: 46,
            child: Row(
              children: [
                _badge(language.code, isCurrent: language.code == selected),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    language.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: language.code == selected ? FontWeight.w700 : FontWeight.w500,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
                if (language.code == selected) Icon(Icons.check_rounded, size: 18, color: AppColors.primary),
              ],
            ),
          ),
      ],
      child: Container(
        height: 32,
        padding: const EdgeInsets.fromLTRB(5, 0, 6, 0),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppShapes.pillRadius),
          border: Border.all(color: AppColors.separator),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _badge(current.code),
            const SizedBox(width: 7),
            Text(
              current.label,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
            ),
            const SizedBox(width: 1),
            Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.secondaryText),
          ],
        ),
      ),
    );
  }
}

/// The three dots while the check is on its way -- the prototype's own waiting
/// state, as a card in the same place the answer will appear.
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

  /// One dot's opacity through its blink: low, up to full at 30% of the cycle,
  /// back down, then a rest.
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
