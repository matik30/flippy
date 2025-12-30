import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flippy/theme/theme_notifier.dart';
import 'app.dart';

// Hlavný vstup aplikácie. Načíta uloženú tému a spustí aplikáciu v Provider-e.

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themeNotifier = await ThemeNotifier.create();
  runApp(ChangeNotifierProvider.value(
    value: themeNotifier,
    child: const FlippyApp(),
  ));
}
