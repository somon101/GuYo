import '../l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../models/status.dart';
import '../theme/app_colors.dart';
import '../widgets/ios_ui.dart';
import '../widgets/remote_image.dart';

/// Opens the status picker: one emoji and one phrase from the admin's
/// lists, either may be left empty. Returns the saved status, or null if
/// the sheet was closed without saving.
Future<MyStatus?> showStatusPicker(BuildContext context) {
  return showModalBottomSheet<MyStatus>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.canvas,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => const _StatusPickerSheet(),
  );
}

class _StatusPickerSheet extends StatefulWidget {
  const _StatusPickerSheet();

  @override
  State<_StatusPickerSheet> createState() => _StatusPickerSheetState();
}

class _StatusPickerSheetState extends State<_StatusPickerSheet> {
  StatusOptions? _options;
  String? _error;
  int? _emojiId;
  int? _phraseId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final options = await ApiClient.instance.fetchStatusOptions();
      if (!mounted) return;
      setState(() {
        _options = options;
        _emojiId = options.mine.emojiId;
        _phraseId = options.mine.phraseId;
      });
    } catch (_) {
      if (mounted) setState(() => _error = tr('Не удалось загрузить статусы'));
    }
  }

  Future<void> _save({bool clear = false}) async {
    setState(() => _saving = true);
    try {
      final saved = await ApiClient.instance.updateMyStatus(
        emojiId: clear ? null : _emojiId,
        phraseId: clear ? null : _phraseId,
      );
      if (mounted) Navigator.of(context).pop(saved);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Не удалось сохранить статус'))));
    }
  }

  String? get _emojiUrl {
    for (final e in _options?.emojis ?? const <StatusEmojiOption>[]) {
      if (e.id == _emojiId) return e.imageUrl;
    }
    return null;
  }

  String? get _phraseText {
    for (final p in _options?.phrases ?? const <StatusPhraseOption>[]) {
      if (p.id == _phraseId) return p.text;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final options = _options;
    final height = MediaQuery.of(context).size.height * 0.82;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 5, decoration: BoxDecoration(color: AppColors.muted, borderRadius: BorderRadius.circular(3))),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 2),
            child: Text(tr('Мой статус'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
          ),
          Text(tr('Его видят все в рейтинге'), style: TextStyle(fontSize: 14, color: AppColors.secondaryText)),
          const SizedBox(height: 12),
          Expanded(
            child: options == null
                ? Center(
                    child: _error == null
                        ? const CircularProgressIndicator()
                        : Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(_error!, style: TextStyle(color: AppColors.secondaryText)),
                            const SizedBox(height: 10),
                            FilledButton(onPressed: _load, child: Text(tr('Повторить'))),
                          ]),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      _Preview(emojiUrl: _emojiUrl, text: _phraseText),
                      const SizedBox(height: 18),
                      IosSection(
                        header: tr('Эмодзи'),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _EmojiTile(
                                  key: const ValueKey('status-emoji-none'),
                                  selected: _emojiId == null,
                                  onTap: () => setState(() => _emojiId = null),
                                  child: Icon(Icons.block_rounded, color: AppColors.muted, size: 26),
                                ),
                                for (final e in options.emojis)
                                  _EmojiTile(
                                    key: ValueKey('status-emoji-${e.id}'),
                                    selected: _emojiId == e.id,
                                    onTap: () => setState(() => _emojiId = e.id),
                                    child: e.imageUrl == null
                                        ? const SizedBox.shrink()
                                        : RemoteImage(url: e.imageUrl!, width: 38, height: 38, fallbackBuilder: () => const SizedBox.shrink()),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      IosSection(
                        header: tr('Фраза'),
                        children: [
                          IosCheckRow(
                            key: const ValueKey('status-phrase-none'),
                            title: tr('Без фразы'),
                            selected: _phraseId == null,
                            onTap: () => setState(() => _phraseId = null),
                          ),
                          for (final p in options.phrases)
                            IosCheckRow(
                              key: ValueKey('status-phrase-${p.id}'),
                              title: p.text,
                              selected: _phraseId == p.id,
                              onTap: () => setState(() => _phraseId = p.id),
                            ),
                        ],
                      ),
                    ],
                  ),
          ),
          if (options != null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    key: const ValueKey('status-save'),
                    onPressed: _saving ? null : () => _save(),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                        : Text(tr('Сохранить'), style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// How the status will look to others: the bubble they see on tap.
class _Preview extends StatelessWidget {
  final String? emojiUrl;
  final String? text;
  const _Preview({required this.emojiUrl, required this.text});

  @override
  Widget build(BuildContext context) {
    final empty = emojiUrl == null && text == null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: AppShapes.cardShadow),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (emojiUrl != null) ...[
            RemoteImage(url: emojiUrl!, width: 30, height: 30, fallbackBuilder: () => const SizedBox.shrink()),
            if (text != null) const SizedBox(width: 10),
          ],
          if (text != null)
            Flexible(
              child: Text(text!, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
            ),
          if (empty) Text(tr('Статус не выбран'), style: TextStyle(fontSize: 15, color: AppColors.secondaryText)),
        ],
      ),
    );
  }
}

class _EmojiTile extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  const _EmojiTile({super.key, required this.selected, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return IosPressable(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 58,
        height: 58,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.violetSurface : AppColors.canvas,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? AppColors.primary : Colors.transparent, width: 2),
        ),
        child: child,
      ),
    );
  }
}
