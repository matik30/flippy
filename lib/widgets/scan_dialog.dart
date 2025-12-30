import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flippy/theme/fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io' as io;
import 'dart:io' as dart_io;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flippy/features/home/home_screen.dart';
import 'package:path_provider/path_provider.dart';

/// Dialóg pre import učebnice — ponúka možnosť otvoriť QR skener alebo importovať JSON súbor z disku.
class ScanDialog extends StatelessWidget {
  const ScanDialog({super.key});

  /// Vyberie JSON súbor cez FilePicker, overí a uloží ho do priečinka aplikácie a zaznamená ho v pref-s
  Future<void> _pickFileAndSave(BuildContext context) async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      String content;
      final file = result.files.first;
      if (file.bytes != null) {
        // načítanie bajtov a dekódovanie ako UTF-8
        content = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        // načítanie surových bajtov a explicitné dekódovanie ako UTF-8
        final bytes = await io.File(file.path!).readAsBytes();
        content = utf8.decode(bytes);
      } else {
        messenger.showSnackBar(const SnackBar(content: Text('Nepodarilo sa načítať súbor')));
        return;
      }

      // odstránenie BOM, ak je prítomný
      if (content.isNotEmpty && content.codeUnitAt(0) == 0xFEFF) {
        content = content.substring(1);
      }

      // overenie platnosti JSON
      jsonDecode(content);

      // uloženie súboru do priečinka dokumentov aplikácie
      final docsDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filename = 'imported_$timestamp.json';
      final filePath = '${docsDir.path}/$filename';
      await dart_io.File(filePath).writeAsString(content, encoding: utf8);

      // zaznamenanie importovaného názvu súboru do zoznamu SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final importedList = prefs.getStringList('imported_textbooks') ?? <String>[];
      importedList.add(filePath);
      await prefs.setStringList('imported_textbooks', importedList);

      // zavretie dialógu ScanDialog
      nav.pop();

      // zobrazenie modálneho dialógu, aby používateľ videl výsledok importu, potom navigácia domov s časovou pečiatkou na nútené obnovenie
      final rootCtx = nav.context;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog<void>(
          context: rootCtx,
          barrierDismissible: false,
          builder: (dialogCtx) {
            return AlertDialog(
              title: const Text('Import úspešný'),
              content: const Text('Kniha bola úspešne importovaná.'),
              actions: [
                TextButton(
                  onPressed: () {
                    // zatvorenie dialógu a navigácia domov s obnovenou HomePage, aby sa načítali importované dáta
                    Navigator.of(dialogCtx).pop();
                    Navigator.of(rootCtx).pushReplacement(
                      MaterialPageRoute(builder: (_) => const HomePage()),
                    );
                  },
                  child: const Text('Zavrieť'),
                ),
              ],
            );
          },
        );
      });
    } catch (e) {
      // použitie zachyteného messengeru na vyhnutie sa používaniu kontextu po asynchrónnych medzerách
      messenger.showSnackBar(SnackBar(content: Text('Chyba pri importe súboru: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    /// Vykreslí jednoduché tlačidlá: Otvoriť skener, Importovať JSON a Zatvoriť
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Čo chceš urobiť?', style: AppTextStyles.chapter),
            const SizedBox(height: 20),

            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                context.go('/qr');
              },
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('   Otvoriť skener  '),
            ),

            const SizedBox(height: 10),

            ElevatedButton.icon(
              onPressed: () => _pickFileAndSave(context),
              icon: const Icon(Icons.upload_file),
              label: const Text('Importovať JSON'),
            ),

            const SizedBox(height: 20),

            Align(
              alignment: Alignment.bottomRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Zavrieť'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
