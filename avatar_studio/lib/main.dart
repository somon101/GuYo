import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'state/services.dart';
import 'state/storage.dart';
import 'state/studio.dart';
import 'ui/home.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final docs = await getApplicationDocumentsDirectory();
  final studio = Studio(FileStorage(Directory('${docs.path}/avatar_studio')), SystemFileServices());
  await studio.load();
  runApp(StudioApp(studio));
}

class StudioApp extends StatelessWidget {
  final Studio studio;
  const StudioApp(this.studio, {super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: studio,
        builder: (_, _) {
          final t = studio.p.settings.theme;
          return MaterialApp(
            title: 'Студия аватаров',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light),
            darkTheme: buildTheme(Brightness.dark),
            themeMode: t == 'dark' ? ThemeMode.dark : (t == 'light' ? ThemeMode.light : ThemeMode.system),
            home: HomePage(studio),
          );
        },
      );
}
