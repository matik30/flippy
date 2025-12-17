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

class ScanDialog extends StatelessWidget {
  const ScanDialog({super.key});

  Future<void> _pickFileAndSave(BuildContext context) async {
    // capture context-bound objects before async gaps
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
        // decode bytes as UTF-8 to avoid mojibake
        content = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        // read raw bytes and decode explicitly as UTF-8
        final bytes = await io.File(file.path!).readAsBytes();
        content = utf8.decode(bytes);
      } else {
        messenger.showSnackBar(const SnackBar(content: Text('Nepodarilo sa načítať súbor')));
        return;
      }

      // strip BOM if present
      if (content.isNotEmpty && content.codeUnitAt(0) == 0xFEFF) {
        content = content.substring(1);
      }

      // validate JSON
      jsonDecode(content);

      // save file into app documents directory
      final docsDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filename = 'imported_$timestamp.json';
      final filePath = '${docsDir.path}/$filename';
      await dart_io.File(filePath).writeAsString(content, encoding: utf8);

      // record imported filename in SharedPreferences list
      final prefs = await SharedPreferences.getInstance();
      final importedList = prefs.getStringList('imported_textbooks') ?? <String>[];
      importedList.add(filePath);
      await prefs.setStringList('imported_textbooks', importedList);

      // keep legacy key as well for compatibility
      // do not overwrite legacy single-key; use imported_textbooks list instead
      // await prefs.setString('textbook_json', content);

      // close the ScanDialog
      nav.pop();

      // show a modal dialog so the user sees the import result, then navigate home with a timestamp to force reload
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
                    // close dialog and replace root with a fresh HomePage so it reloads imported data
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
      // use captured messenger to avoid using context after async gaps
      messenger.showSnackBar(SnackBar(content: Text('Chyba pri importe súboru: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
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
