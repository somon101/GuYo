import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/dictionary.dart';
import '../models/quest.dart';
import 'quest_attempt_screen.dart';

const Map<String, String> _exerciseLabels = {
  'true_or_false': 'Правда или ложь',
  'matching': 'Сопоставление',
  'build_word': 'Собери слово',
  'speaking_word': 'Произнеси слово',
  'listen_word': 'Услышь слово',
};

/// "Квесты": a system entirely separate from "Уроки" -- a quest targets
/// whichever ONE word of this dictionary is currently at its configured
/// word level (backend/app/quests/), never a fixed word set. The backend
/// decides which quests are currently attemptable; this screen only lists
/// and launches them.
class QuestsScreen extends StatefulWidget {
  final GuyoDictionary dictionary;
  const QuestsScreen({super.key, required this.dictionary});

  @override
  State<QuestsScreen> createState() => _QuestsScreenState();
}

class _QuestsScreenState extends State<QuestsScreen> {
  bool _isLoading = true;
  String? _loadError;
  List<AvailableQuest> _quests = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final quests = await ApiClient.instance.fetchAvailableQuests(widget.dictionary.id);
      if (!mounted) return;
      setState(() {
        _quests = quests;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Не удалось загрузить квесты';
      });
    }
  }

  Future<void> _openQuest(AvailableQuest quest) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuestAttemptScreen(dictionary: widget.dictionary, questId: quest.id, questName: quest.name),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Квесты')),
      body: SafeArea(
        child: RefreshIndicator(onRefresh: _load, child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return ListView(children: const [SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))]);
    }
    if (_loadError != null) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: const Text('Повторить')),
              ],
            ),
          ),
        ],
      );
    }
    if (_quests.isEmpty) {
      return ListView(
        children: const [
          Padding(
            padding: EdgeInsets.all(24),
            child: Text('Квестов пока нет', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [for (final quest in _quests) _QuestTile(quest: quest, onTap: () => _openQuest(quest))],
    );
  }
}

class _QuestTile extends StatelessWidget {
  final AvailableQuest quest;
  final VoidCallback onTap;
  const _QuestTile({required this.quest, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final available = quest.available;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: available ? Colors.indigo.shade100 : Colors.grey.shade300),
      ),
      child: InkWell(
        onTap: available ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(
                Icons.flag_rounded,
                color: available ? Colors.indigo.shade400 : Colors.grey.shade400,
                size: 28,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      quest.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: available ? Colors.black87 : Colors.black45,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Уровень «${quest.wordLevelName}» · ${_exerciseLabels[quest.exerciseKey] ?? quest.exerciseKey}',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    if (!available) ...[
                      const SizedBox(height: 2),
                      const Text(
                        'Пока нет подходящих слов',
                        style: TextStyle(fontSize: 11, color: Colors.black38),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '+${quest.rewardPoints}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.amber.shade800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
