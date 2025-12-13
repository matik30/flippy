import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flippy/theme/colors.dart';
import 'package:flippy/theme/fonts.dart';
import 'package:flippy/widgets/scan_dialog.dart';

Map<String, dynamic> _parseManifest(String s) => jsonDecode(s) as Map<String, dynamic>;

Future<List<String>> loadJsonPaths() async {
  try {
    final manifestContent = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifestMap =
        await compute(_parseManifest, manifestContent);

    return manifestMap.keys
        .where(
          (p) => p.startsWith('assets/data/') && p.endsWith('.json'),
        )
        .toList();
  } catch (_) {
    try {
      final indexContent =
          await rootBundle.loadString('assets/data/index.json');
      final list = jsonDecode(indexContent) as List<dynamic>;
      return list.cast<String>();
    } catch (_) {
      return const [];
    }
  }
}

Future<Map<String, dynamic>> loadTextbook(String path) async {
  final jsonString = await rootBundle.loadString(path);
  final jsonData = jsonDecode(jsonString);
  return jsonData['textbook'];
}

Future<dynamic> _readJsonFileUtf8(String path) async {
  // Read as bytes and decode as UTF-8 to avoid platform-dependent encodings
  final bytes = await io.File(path).readAsBytes();
  var s = utf8.decode(bytes);
  // Strip UTF-8 BOM if present
  if (s.isNotEmpty && s.codeUnitAt(0) == 0xFEFF) {
    s = s.substring(1);
  }
  return jsonDecode(s);
}

Future<List<Map<String, dynamic>>> loadAllTextbooks() async {
  final paths = await loadJsonPaths();
  final textbooks = await Future.wait(paths.map(loadTextbook));

  try {
    final prefs = await SharedPreferences.getInstance();
    final imported = prefs.getStringList('imported_textbooks') ?? [];

    for (final path in imported) {
      try {
        final data = await _readJsonFileUtf8(path);
        final tb = data['textbook'];
        if (tb is Map<String, dynamic>) {
          final m = Map<String, dynamic>.from(tb);
          m['__imported__'] = true;
          m['__source__'] = path; // provide a stable source identifier for imported books
          m['__file__'] = path;
          textbooks.insert(0, m);
        }
      } catch (_) {}
    }
  } catch (_) {}

  return textbooks;
}

Future<ImageInfo> loadImageInfo(String assetPath) async {
  final completer = Completer<ImageInfo>();
  final stream = AssetImage(assetPath)
      .resolve(const ImageConfiguration());

  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      completer.complete(info);
      stream.removeListener(listener);
    },
    onError: (e, _) {
      completer.completeError(e);
      stream.removeListener(listener);
    },
  );

  stream.addListener(listener);
  return completer.future;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<Map<String, dynamic>>> _textbooksFuture;

  @override
  void initState() {
    super.initState();
    _textbooksFuture = loadAllTextbooks();
  }

  Future<void> _openImportManager() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => const _ImportedManagerDialog(),
    );

    if (changed == true && mounted) {
      setState(() {
        _textbooksFuture = loadAllTextbooks();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: () {
          showDialog(context: context, builder: (_) => const ScanDialog());
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.accent, AppColors.background],
            stops: const [0.0, 0.15],
          ),
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: false,
            centerTitle: true,
            title: Text('Učebnice', style: AppTextStyles.chapter),
            actions: [
              IconButton(
                icon: const Icon(Icons.import_contacts),
                onPressed: _openImportManager,
              ),
            ],
          ),
          body: FutureBuilder<List<Map<String, dynamic>>>(
            future: _textbooksFuture,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final books = snap.data ?? [];
              if (books.isEmpty) {
                return const Center(child: Text('Žiadne učebnice'));
              }

              return GridView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: books.length,
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 20,
                ),
                itemBuilder: (_, i) {
                  final book = books[i];
                  final cover = book['coverImage'];

                  return FutureBuilder<ImageInfo>(
                    future: loadImageInfo(cover),
                    builder: (_, img) {
                      if (!img.hasData) return const SizedBox.shrink();

                      final info = img.data!;
                      final aspect =
                          info.image.width / info.image.height;

                      return GestureDetector(
                        onTap: () =>
                            // pass the textbook explicitly under 'textbook' so
                            // downstream screens can read full textbook map
                            context.go('/chapters', extra: {'textbook': book}),
                        child: AspectRatio(
                          aspectRatio: aspect,
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: AppColors.text, width: 2),
                              borderRadius: BorderRadius.circular(13),
                              image: DecorationImage(
                                image: AssetImage(cover),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ImportedManagerDialog extends StatefulWidget {
  const _ImportedManagerDialog();

  @override
  State<_ImportedManagerDialog> createState() =>
      _ImportedManagerDialogState();
}

class _ImportedManagerDialogState
    extends State<_ImportedManagerDialog> {
  List<String> _paths = [];
  final Map<String, String> _titles = {};
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _paths = List<String>.from(prefs.getStringList('imported_textbooks') ?? []);

    final Map<String, String> titles = {};
    for (final path in _paths) {
      try {
        final data = await _readJsonFileUtf8(path);
        final tb = data['textbook'];
        String title = '';
        if (tb is Map<String, dynamic>) {
          title = (tb['title'] ?? tb['name'] ?? '') as String? ?? '';
        }
        if (title.isEmpty) title = path.split('/').last;
        titles[path] = title;
      } catch (_) {
        titles[path] = path.split('/').last;
      }
    }

    _titles.clear();
    _titles.addAll(titles);

    if (mounted) setState(() {});
  }

  Future<void> _delete(int i) async {
    final prefs = await SharedPreferences.getInstance();
    final path = _paths[i];

    try {
      final f = io.File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}

    _paths.removeAt(i);
    _titles.remove(path);
    await prefs.setStringList('imported_textbooks', _paths);
    _changed = true;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Importované učebnice'),
      content: SizedBox(
        width: double.maxFinite,
        child: _paths.isEmpty
            ? const Text('Žiadne importované učebnice')
            : ListView.builder(
                shrinkWrap: true,
                itemCount: _paths.length,
                itemBuilder: (_, i) {
                  final path = _paths[i];
                  final title = _titles[path] ?? path.split('/').last;
                  return ListTile(
                    title: Text(title),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _delete(i),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_changed),
          child: const Text('Zavrieť'),
        ),
      ],
    );
  }
}
