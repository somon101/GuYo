import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/dictionary.dart';
import 'dictionary_words_screen.dart';

class DictionaryListScreen extends StatefulWidget {
  const DictionaryListScreen({super.key});

  @override
  State<DictionaryListScreen> createState() => _DictionaryListScreenState();
}

class _DictionaryListScreenState extends State<DictionaryListScreen> {
  late Future<List<GuyoDictionary>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiClient.instance.fetchDictionaries();
  }

  Future<void> _reload() async {
    setState(() {
      _future = ApiClient.instance.fetchDictionaries();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Словарь')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<GuyoDictionary>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Не удалось загрузить словари.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              );
            }
            final dictionaries = snapshot.data ?? [];
            if (dictionaries.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Словарей пока нет', textAlign: TextAlign.center),
                  ),
                ],
              );
            }
            return ListView.separated(
              itemCount: dictionaries.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final d = dictionaries[index];
                return ListTile(
                  title: Text(d.name, style: const TextStyle(fontSize: 18)),
                  subtitle: Text('${d.languageLabel} · ${d.wordCount} слов'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DictionaryWordsScreen(dictionary: d),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
