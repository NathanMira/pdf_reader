import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/ai_config.dart';
import 'screens/library_screen.dart';
import 'services/library_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  final prefs = await SharedPreferences.getInstance();
  final aiConfig = await AiConfig.load();
  final store = LibraryStore(prefs, aiConfig: aiConfig);
  runApp(PdfReaderApp(store: store));
}

class PdfReaderApp extends StatelessWidget {
  const PdfReaderApp({super.key, required this.store});

  final LibraryStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF阅读',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B4D3E)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7DCEA0),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: LibraryScreen(store: store),
    );
  }
}
