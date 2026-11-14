import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/text_check.dart';
import '../services/text_check_settings.dart';
import '../theme/app_colors.dart';
import '../widgets/in_app_banner.dart';

/// «Проверка текста» (variant C): a full screen opened over the app, no bottom bar.
///
/// - Writing: the field takes the screen; below it «Кому» (who the message is for), the counter
///   and one button «Проверить». Everything else (formality, punctuation, the language of the
///   explanations, the writer's gender) is in one sheet behind the gear.
/// - The answer: the writer's own text with the mistakes marked right in it; tap a mark (or the
///   arrows) to see the fix and why; a switch shows the corrected text; one main button copies it.
///
/// Nothing here changes anything else in the app: the interface language is never touched, and no
/// score, streak or achievement is involved -- this is a writing aid, not an exercise. Nothing is
/// kept between checks (no history); the addressee is asked afresh for every message.
class TextCheckScreen extends StatefulWidget {
  const TextCheckScreen({super.key});

  @override
  State<TextCheckScreen> createState() => _TextCheckScreenState();
}

class _TextCheckScreenState extends State<TextCheckScreen> {
  /// Used until the backend says otherwise -- the real limit is the admin's own `max_chars`.
  static const int _fallbackMaxChars = 500;

  final _controller = TextEditingController();
  TextCheckSettings _settings = TextCheckSettings.defaults();
  TextCheckInfo? _info;

  /// null means «не знаю»; never carried from one message to the next.
  String? _addressee;

  bool _busy = false;

  /// The message that was checked, the answer to it and, if it failed, why.
  String _question = '';
  TextCheckResult? _result;
  String? _errorMessage;

  /// Result view: 0 = the text as written (mistakes marked), 1 = the corrected text.
  int _tab = 0;

  /// The mistake whose explanation is shown.
  int _picked = 0;

  final List<TapGestureRecognizer> _taps = [];

  bool get _showingAnswer => _busy || _result != null || _errorMessage != null;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
    _loadSettings();
    _loadInfo();
  }

  @override
  void dispose() {
    for (final t in _taps) {
      t.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settings = await TextCheckSettings.load();
    if (mounted) setState(() => _settings = settings);
  }

  Future<void> _loadInfo() async {
    try {
      final info = await ApiClient.instance.fetchTextCheckInfo();
      if (mounted) setState(() => _info = info);
    } catch (_) {
      // Without it the screen still works on its own defaults: the backend enforces the real limit.
    }
  }

  int get _maxChars => _info?.maxChars ?? _fallbackMaxChars;
  bool get _checkerDisabled => _info != null && !_info!.enabled;
  bool get _limitUsedUp => _info != null && !_info!.unlimited && _info!.remaining != null && _info!.remaining! <= 0;

  void _saveSettings(TextCheckSettings next) {
    setState(() => _settings = next);
    next.save();
  }

  void _confirm(String message) {
    InAppBanner.show(body: message, visibleFor: InAppBanner.confirmationVisibleFor, opensInbox: false);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy || _checkerDisabled || _limitUsedUp) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final addressee = _addressee ?? 'unknown';
    setState(() {
      _busy = true;
      _question = text;
      _result = null;
      _errorMessage = null;
      _tab = 0;
      _picked = 0;
      // Every message is asked afresh: who it is for is never remembered.
      _addressee = null;
    });
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
      // The backend's own wording is shown as-is (e.g. «the daily limit is used up»).
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = tr('Ошибка сети. Проверьте интернет.');
          _busy = false;
        });
      }
    }
  }

  /// «Править»: back to the field with the text that was checked.
  void _edit() {
    _controller.text = _question;
    _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    setState(() {
      _result = null;
      _errorMessage = null;
      _busy = false;
    });
  }

  Future<void> _copyCorrected(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _confirm(tr('Текст скопирован'));
  }

  String _addresseeLabel() => switch (_addressee) {
        'male' => tr('мужчине'),
        'female' => tr('женщине'),
        _ => tr('любому'),
      };

  // ---------------------------------------------------------------- settings

  Future<void> _openSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void change(TextCheckSettings next) {
            _saveSettings(next);
            setSheet(() {});
          }

          Widget row(Widget left, Widget right) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(children: [Expanded(child: left), const SizedBox(width: 12), right]),
              );
          Widget title(String t, [String? sub]) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: AppColors.primaryDark)),
                if (sub != null) Text(sub, style: TextStyle(fontSize: 12.5, color: AppColors.secondaryText)),
              ]);
          Widget divider() => Divider(height: 1, thickness: 1, color: AppColors.cardBorder);
          final language = textCheckLanguages.firstWhere((l) => l.code == _settings.explanationLanguage, orElse: () => textCheckLanguages.first);
          return SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              decoration: BoxDecoration(color: AppColors.canvas, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.progressTrack, borderRadius: BorderRadius.circular(99)))),
                const SizedBox(height: 14),
                Text(tr('Настройки проверки'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppColors.primaryDark)),
                const SizedBox(height: 6),
                row(
                  title(tr('Формальность'), tr('Проверять обращение на «Вы»')),
                  Switch(key: const ValueKey('tc-formality'), value: _settings.formality == 'formal', onChanged: (v) => change(_settings.copyWith(formality: v ? 'formal' : ''))),
                ),
                divider(),
                row(
                  title(tr('Пунктуация'), tr('Проверять запятые и знаки')),
                  Switch(key: const ValueKey('tc-punctuation'), value: _settings.checkPunctuation, onChanged: (v) => change(_settings.copyWith(checkPunctuation: v))),
                ),
                divider(),
                row(
                  title(tr('Язык объяснений')),
                  PopupMenuButton<String>(
                    key: const ValueKey('text-check-language'),
                    onSelected: (code) => change(_settings.copyWith(explanationLanguage: code)),
                    itemBuilder: (_) => [for (final l in textCheckLanguages) PopupMenuItem(value: l.code, child: Text(l.label))],
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(language.label, style: TextStyle(fontSize: 15, color: AppColors.secondaryText)),
                      Icon(Icons.expand_more_rounded, size: 20, color: AppColors.secondaryText),
                    ]),
                  ),
                ),
                divider(),
                row(
                  title(tr('Я пишу как')),
                  _Segment<String>(
                    values: const ['male', 'female'],
                    selected: _settings.userGender,
                    label: (v) => v == 'male' ? tr('Мужчина') : tr('Женщина'),
                    keyOf: (v) => ValueKey('tc-gender-$v'),
                    onTap: (v) => change(_settings.copyWith(userGender: v)),
                  ),
                ),
                if (_info != null && !_info!.unlimited && _info!.dailyLimit != null) ...[
                  divider(),
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _limitUsedUp ? tr('Проверки на сегодня закончились') : tr('Осталось проверок сегодня: {0} из {1}', [_info!.remaining ?? 0, _info!.dailyLimit]),
                      style: TextStyle(fontSize: 12.5, color: AppColors.secondaryText),
                    ),
                  ),
                ],
              ]),
            ),
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(key: const ValueKey('text-check-back'), color: AppColors.primaryDark),
        title: Text(tr('Проверка текста'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
        actions: [
          IconButton(
            key: const ValueKey('text-check-settings'),
            tooltip: tr('Настройки проверки'),
            icon: Icon(Icons.tune_rounded, color: AppColors.secondaryText),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: SafeArea(child: _checkerDisabled ? _unavailable() : (_showingAnswer ? _answer() : _editor())),
    );
  }

  Widget _unavailable() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(tr('Проверка текста сейчас недоступна'), textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
            const SizedBox(height: 6),
            Text(tr('Загляните позже.'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.secondaryText)),
          ]),
        ),
      );

  // The writing view: the field, who it is for, the counter and one button.
  Widget _editor() {
    final text = _controller.text.trim();
    final canSend = text.isNotEmpty && !_limitUsedUp;
    return Column(children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: TextField(
            key: const ValueKey('text-check-input'),
            controller: _controller,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            maxLength: _maxChars,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(fontSize: 18, height: 1.5, color: AppColors.primaryDark),
            cursorColor: AppColors.primary,
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: tr('Введите текст...'),
              hintStyle: TextStyle(color: AppColors.secondaryText),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: Column(children: [
          Row(children: [
            PopupMenuButton<String?>(
              key: const ValueKey('text-check-addressee'),
              onSelected: (v) => setState(() => _addressee = v),
              itemBuilder: (_) => [
                PopupMenuItem<String?>(value: null, child: Text(tr('Любому'))),
                PopupMenuItem<String?>(value: 'male', child: Text(tr('Мужчине'))),
                PopupMenuItem<String?>(value: 'female', child: Text(tr('Женщине'))),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(tr('Кому: {0}', [_addresseeLabel()]), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.secondaryText)),
                  Icon(Icons.expand_more_rounded, size: 18, color: AppColors.secondaryText),
                ]),
              ),
            ),
            const Spacer(),
            Text('${text.length} / $_maxChars', style: TextStyle(fontSize: 13, color: AppColors.secondaryText, fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
          if (_limitUsedUp)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(tr('Проверки на сегодня закончились'), style: TextStyle(fontSize: 13, color: AppColors.danger))),
          _Button(key: const ValueKey('text-check-send'), label: tr('Проверить'), onTap: canSend && !_busy ? _send : null),
        ]),
      ),
    ]);
  }

  // The answer view.
  Widget _answer() {
    final result = _result;
    final errors = result?.errors ?? const <TextCheckError>[];
    final hasErrors = result?.hasErrors ?? false;
    final corrected = result?.correctedText ?? '';
    return Column(children: [
      if (hasErrors)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
          child: _Segment<int>(
            values: const [0, 1],
            selected: _tab,
            expand: true,
            label: (v) => v == 0 ? tr('Исходный') : tr('Исправленный'),
            keyOf: (v) => ValueKey('tc-tab-$v'),
            onTap: (v) => setState(() => _tab = v),
          ),
        ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 12), children: [
          if (_busy) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                const SizedBox(width: 10),
                Text(tr('Проверяю…'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.secondaryText)),
              ]),
            ),
            _textCard(Text(_question, style: TextStyle(fontSize: 18, height: 1.7, color: AppColors.secondaryText))),
          ] else if (_errorMessage != null) ...[
            _textCard(Text(_errorMessage!, style: TextStyle(fontSize: 16, height: 1.5, color: AppColors.danger))),
          ] else if (result != null) ...[
            if (!hasErrors)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success),
                  const SizedBox(width: 8),
                  Text(result.summary.isEmpty ? tr('Ошибок нет') : result.summary, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.success)),
                ]),
              ),
            _textCard(
              hasErrors && _tab == 1
                  ? Text(corrected, key: const ValueKey('text-check-corrected'), style: TextStyle(fontSize: 18, height: 1.7, color: AppColors.primaryDark))
                  : Text.rich(_markedText(_question, errors), key: const ValueKey('text-check-original'), style: TextStyle(fontSize: 18, height: 1.7, color: AppColors.primaryDark)),
            ),
            if (hasErrors && _tab == 0) ...[
              const SizedBox(height: 12),
              _mistakeCard(errors),
            ],
          ],
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
        child: Column(children: [
          if (hasErrors && corrected.isNotEmpty) _Button(key: const ValueKey('text-check-copy'), label: tr('Копировать исправленный'), icon: Icons.copy_rounded, onTap: () => _copyCorrected(corrected)),
          TextButton(
            key: const ValueKey('text-check-edit'),
            onPressed: _busy ? null : _edit,
            child: Text(tr('Править'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primary)),
          ),
        ]),
      ),
    ]);
  }

  Widget _textCard(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
        child: child,
      );

  /// The writer's text with each mistake's fragment marked in place (found one after another).
  TextSpan _markedText(String text, List<TextCheckError> errors) {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (var i = 0; i < errors.length; i++) {
      final fragment = errors[i].fragment;
      if (fragment.isEmpty) continue;
      final at = text.indexOf(fragment, cursor);
      if (at < 0) continue;
      if (at > cursor) spans.add(TextSpan(text: text.substring(cursor, at)));
      final tap = TapGestureRecognizer()..onTap = () => setState(() => _picked = i);
      _taps.add(tap);
      final selected = i == _picked;
      spans.add(TextSpan(
        text: fragment,
        recognizer: tap,
        style: TextStyle(
          backgroundColor: AppColors.danger.withValues(alpha: selected ? 0.22 : 0.12),
          decoration: TextDecoration.underline,
          decorationColor: AppColors.danger,
          decorationThickness: 2,
        ),
      ));
      cursor = at + fragment.length;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return TextSpan(children: spans);
  }

  /// The picked mistake: what it was, what it should be, which kind and why; arrows go through them.
  Widget _mistakeCard(List<TextCheckError> errors) {
    final index = _picked.clamp(0, errors.length - 1);
    final e = errors[index];
    return Container(
      key: const ValueKey('text-check-mistake'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.primary, width: 1.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              textCheckGroupTitle(e.group, _settings.explanationLanguage),
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.secondaryText),
            ),
          ),
          if (errors.length > 1) ...[
            _Arrow(key: const ValueKey('tc-prev'), icon: Icons.chevron_left_rounded, onTap: index > 0 ? () => setState(() => _picked = index - 1) : null),
            Text(tr('Ошибка {0} из {1}', [index + 1, errors.length]), style: TextStyle(fontSize: 12.5, color: AppColors.secondaryText)),
            _Arrow(key: const ValueKey('tc-next'), icon: Icons.chevron_right_rounded, onTap: index < errors.length - 1 ? () => setState(() => _picked = index + 1) : null),
          ],
        ]),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(children: [
            if (e.fragment.isNotEmpty) TextSpan(text: e.fragment, style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700, decoration: TextDecoration.lineThrough, decorationThickness: 2)),
            if (e.fragment.isNotEmpty && e.correct.isNotEmpty) TextSpan(text: '  →  ', style: TextStyle(color: AppColors.secondaryText)),
            if (e.correct.isNotEmpty) TextSpan(text: e.correct, style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w700)),
          ]),
          style: const TextStyle(fontSize: 16.5, height: 1.4),
        ),
        if (e.explanation.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(e.explanation, style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.secondaryText)),
        ],
      ]),
    );
  }
}

/// The screen's one filled button (indigo pill); greyed out when it has nothing to do.
class _Button extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  const _Button({super.key, required this.label, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: on ? AppColors.primary : AppColors.progressTrack, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 18, color: Colors.white), const SizedBox(width: 8)],
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: on ? Colors.white : AppColors.secondaryText, fontSize: 15.5, fontWeight: FontWeight.w700))),
        ]),
      ),
    );
  }
}

/// A quiet segmented switch.
class _Segment<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final Key Function(T) keyOf;
  final void Function(T) onTap;
  final bool expand;
  const _Segment({required this.values, required this.selected, required this.label, required this.keyOf, required this.onTap, this.expand = false});

  @override
  Widget build(BuildContext context) {
    final items = [
      for (final v in values)
        GestureDetector(
          key: keyOf(v),
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap(v),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: v == selected ? AppColors.surface : null, borderRadius: BorderRadius.circular(8)),
            child: Text(label(v), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: v == selected ? AppColors.primaryDark : AppColors.secondaryText)),
          ),
        ),
    ];
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: AppColors.violetSurface, borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, children: [for (final i in items) expand ? Expanded(child: i) : i]),
    );
  }
}

class _Arrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _Arrow({super.key, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(2), child: Icon(icon, size: 22, color: onTap == null ? AppColors.progressTrack : AppColors.primary)),
      );
}
