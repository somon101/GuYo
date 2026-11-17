import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../l10n/l10n.dart';
import '../../models/mini_phrase.dart';
import '../../theme/app_colors.dart';
import '../audio_button.dart';
import 'mini_phrase_style.dart';

/// The explanation screen of one mini-phrase: the phrase itself (each part
/// in its role's colour) and its translation, then "part + part = phrase",
/// then the template's explanation text -- written once for many phrases
/// and already filled in by the server.
class MiniPhraseExplanation extends StatelessWidget {
  final MiniPhrase phrase;
  final VoidCallback onNext;
  final String nextLabel;

  const MiniPhraseExplanation({super.key, required this.phrase, required this.onNext, required this.nextLabel});

  @override
  Widget build(BuildContext context) {
    final parts = phrase.parts;
    final hasAudio = phrase.audioUrl != null && phrase.audioUrl!.isNotEmpty;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppShapes.bannerRadius),
                border: Border.all(color: AppColors.cardBorder),
                boxShadow: AppShapes.cardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.violetSurface,
                      borderRadius: BorderRadius.circular(AppShapes.pillRadius),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome_rounded, size: 15, color: AppColors.primary),
                        const SizedBox(width: 5),
                        Text(
                          tr('Мини-фраза'),
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.primary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (var i = 0; i < parts.length; i++)
                              MiniPhraseAppear(
                                delay: Duration(milliseconds: 90 * i),
                                child: Text(
                                  parts[i].text,
                                  style: TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800,
                                    height: 1.15,
                                    color: miniPhraseRoleColor(parts[i].role),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (hasAudio) AudioButton(url: ApiClient.instance.mediaUrl(phrase.audioUrl!)),
                    ],
                  ),
                  if (phrase.translation != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      phrase.translation!,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: AppColors.secondaryText),
                    ),
                  ],
                  const SizedBox(height: 22),
                  // part + part = phrase
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.start,
                    spacing: 8,
                    runSpacing: 10,
                    children: [
                      for (var i = 0; i < parts.length; i++) ...[
                        if (i > 0) _Operator('+', delay: Duration(milliseconds: 250 + 140 * i)),
                        MiniPhraseAppear(
                          delay: Duration(milliseconds: 250 + 140 * i),
                          child: MiniPhrasePartChip(text: parts[i].text, role: parts[i].role, caption: parts[i].translation),
                        ),
                      ],
                      _Operator('=', delay: Duration(milliseconds: 250 + 140 * parts.length)),
                      MiniPhraseAppear(
                        delay: Duration(milliseconds: 330 + 140 * parts.length),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            phrase.text,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (phrase.explanation.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.violetSurface,
                        borderRadius: BorderRadius.circular(AppShapes.rowRadius),
                      ),
                      child: Text.rich(
                        TextSpan(children: [for (final s in phrase.explanation) _span(s)]),
                        style: TextStyle(fontSize: 15.5, height: 1.45, color: AppColors.primaryDark),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                key: const ValueKey('mini-phrase-next'),
                onPressed: onNext,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(nextLabel, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  InlineSpan _span(MiniPhraseSegment s) {
    switch (s.kind) {
      case 'part':
        return TextSpan(
          text: s.text,
          style: TextStyle(fontWeight: FontWeight.w800, color: miniPhraseRoleColor(s.role)),
        );
      case 'phrase':
        return TextSpan(text: s.text, style: const TextStyle(fontWeight: FontWeight.w800));
      case 'translation':
        return TextSpan(text: s.text, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.secondaryText));
      default:
        return TextSpan(text: s.text);
    }
  }
}

class _Operator extends StatelessWidget {
  final String symbol;
  final Duration delay;
  const _Operator(this.symbol, {required this.delay});

  @override
  Widget build(BuildContext context) {
    return MiniPhraseAppear(
      delay: delay,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(symbol, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.muted)),
      ),
    );
  }
}
