import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/dictionary.dart';
import '../models/mini_phrase.dart';
import '../theme/app_colors.dart';
import '../widgets/guyo_ui.dart';
import '../widgets/mini_phrases/mini_phrase_session.dart';
import '../widgets/mini_phrases/mini_phrase_style.dart';
import '../widgets/skeleton.dart';

/// Практика → Мини-фразы: every mini-phrase already opened in a lesson, to
/// look at again (explanation) and assemble again. Rating points are given
/// only once per mini-phrase, so practising never farms them.
class MiniPhrasesPracticeScreen extends StatefulWidget {
  final GuyoDictionary dictionary;
  const MiniPhrasesPracticeScreen({super.key, required this.dictionary});

  @override
  State<MiniPhrasesPracticeScreen> createState() => _MiniPhrasesPracticeScreenState();
}

class _MiniPhrasesPracticeScreenState extends State<MiniPhrasesPracticeScreen> {
  late Future<List<MiniPhrase>> _future = ApiClient.instance.fetchOpenMiniPhrases(widget.dictionary.id);

  Future<void> _reload() async {
    setState(() => _future = ApiClient.instance.fetchOpenMiniPhrases(widget.dictionary.id));
    await _future;
  }

  void _practise(List<MiniPhrase> phrases) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _MiniPhrasePracticeRun(phrases: phrases)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Мини-фразы'))),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<MiniPhrase>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SkeletonList(avatar: false);
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 60),
                  GuyoEmptyState(
                    icon: Icons.wifi_off_rounded,
                    title: tr('Не удалось загрузить мини-фразы'),
                    actionLabel: tr('Повторить'),
                    onAction: _reload,
                  ),
                ],
              );
            }
            final phrases = snapshot.data ?? const [];
            if (phrases.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 60),
                  GuyoEmptyState(
                    icon: Icons.extension_rounded,
                    title: tr('Пока нет мини-фраз'),
                    message: tr('Мини-фразы открываются в уроках, когда вы выучите нужные слова.'),
                  ),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () => _practise([...phrases]..shuffle()),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: const Icon(Icons.replay_rounded),
                    label: Text(tr('Повторить все'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 16),
                for (final p in phrases) ...[
                  GuyoCard(
                    onTap: () => _practise([p]),
                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text.rich(
                                TextSpan(children: [
                                  for (var i = 0; i < p.parts.length; i++) ...[
                                    if (i > 0) const TextSpan(text: ' '),
                                    TextSpan(
                                      text: p.parts[i].text,
                                      style: TextStyle(color: miniPhraseRoleColor(p.parts[i].role)),
                                    ),
                                  ],
                                ]),
                                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                              ),
                              if (p.translation != null) ...[
                                const SizedBox(height: 2),
                                Text(p.translation!, style: TextStyle(fontSize: 14.5, color: AppColors.secondaryText)),
                              ],
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MiniPhrasePracticeRun extends StatelessWidget {
  final List<MiniPhrase> phrases;
  const _MiniPhrasePracticeRun({required this.phrases});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Мини-фразы'))),
      body: MiniPhraseSession(phrases: phrases, onDone: () => Navigator.of(context).pop()),
    );
  }
}
