import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'package:flippy/theme/colors.dart';
import 'package:flippy/theme/fonts.dart';
import 'package:flippy/widgets/scan_dialog.dart';
import 'package:flippy/theme/theme_notifier.dart';

// Načíta cesty k JSON súborom z AssetManifest alebo alternatívne z index.json
Map<String, dynamic> _parseManifest(String s) =>
    jsonDecode(s) as Map<String, dynamic>;

Future<List<String>> loadJsonPaths() async {
  try {
    final manifestContent = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifestMap = await compute(
      _parseManifest,
      manifestContent,
    );

    return manifestMap.keys
        .where((p) => p.startsWith('assets/data/') && p.endsWith('.json'))
        .toList();
  } catch (_) {
    try {
      final indexContent = await rootBundle.loadString(
        'assets/data/index.json',
      );
      final list = jsonDecode(indexContent) as List<dynamic>;
      return list.cast<String>();
    } catch (_) {
      return const [];
    }
  }
}

// Načíta metadáta učebnice z asset JSON (vracia 'textbook' objekt)
Future<Map<String, dynamic>> loadTextbook(String path) async {
  final jsonString = await rootBundle.loadString(path);
  final jsonData = jsonDecode(jsonString);
  return jsonData['textbook'];
}

// Načíta JSON súbor z disku a vráti dekódovaný obsah (UTF-8, ošetrenie BOM)
Future<dynamic> _readJsonFileUtf8(String path) async {
  final bytes = await io.File(path).readAsBytes();
  var s = utf8.decode(bytes);
  if (s.isNotEmpty && s.codeUnitAt(0) == 0xFEFF) {
    s = s.substring(1);
  }
  return jsonDecode(s);
}

// Načíta všetky učebnice vrátane importovaných z aplikácie
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
          m['__source__'] = path; // pre prípadnú identifikáciu zdroja
          m['__file__'] = path;
          textbooks.insert(0, m);
        }
      } catch (_) {}
    }
  } catch (_) {}

  return textbooks;
}

// Načíta ImageInfo pre danú cestu (asset alebo súbor), s ošetrením chýb
Future<ImageInfo> loadImageInfo(String path) async {
  final completer = Completer<ImageInfo>();
  ImageProvider provider;
  try {
    if (path.startsWith('assets/')) {
      provider = AssetImage(path);
    } else if (io.File(path).existsSync()) {
      provider = FileImage(io.File(path));
    } else {
      provider = AssetImage(path);
    }
  } catch (_) {
    provider = AssetImage(path);
  }

  final stream = provider.resolve(const ImageConfiguration());

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

// Domovská obrazovka — načítanie a zobrazenie dostupných učebníc,
// vrátane podpory importovaných súborov a správy importov.
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
        backgroundColor: Theme.of(context).colorScheme.primary,
        onPressed: () {
          showDialog(context: context, builder: (_) => const ScanDialog());
        },
        child: Icon(Icons.add, color: Theme.of(context).colorScheme.onPrimary),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.secondary,
              Theme.of(context).colorScheme.surface,
            ],
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
              PopupMenuButton<String>(
                icon: const Icon(Icons.menu),
                onSelected: (v) async {
                  if (v == 'import') return _openImportManager();
                  if (v == 'theme') {
                    final tn = Provider.of<ThemeNotifier>(
                      context,
                      listen: false,
                    );
                    final sel = await showDialog<String>(
                      context: context,
                      builder: (dialogCtx) => SimpleDialog(
                        title: const Text('Vyber motív'),
                        children: [
                          SimpleDialogOption(
                            onPressed: () =>
                                Navigator.of(dialogCtx).pop('blue'),
                            child: Row(
                              children: [
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text('Modrá (základná)'),
                              ],
                            ),
                          ),
                          SimpleDialogOption(
                            onPressed: () => Navigator.of(dialogCtx).pop('red'),
                            child: Row(
                              children: [
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: AppColorsRed.primary,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text('Červená'),
                              ],
                            ),
                          ),
                          SimpleDialogOption(
                            onPressed: () =>
                                Navigator.of(dialogCtx).pop('green'),
                            child: Row(
                              children: [
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: AppColorsGreen.primary,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text('Zelená'),
                              ],
                            ),
                          ),
                          SimpleDialogOption(
                            onPressed: () =>
                                Navigator.of(dialogCtx).pop('orange'),
                            child: Row(
                              children: [
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: AppColorsOrange.primary,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text('Oranžová'),
                              ],
                            ),
                          ),
                          SimpleDialogOption(
                            onPressed: () =>
                                Navigator.of(dialogCtx).pop('turq'),
                            child: Row(
                              children: [
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: AppColorsTurquise.primary,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text('Tyrkysová'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );

                    if (sel != null) await tn.setThemeByKey(sel);
                  }
                },
                itemBuilder: (menuCtx) => [
                  PopupMenuItem(
                    value: 'import',
                    child: Row(
                      children: [
                        Icon(
                          Icons.menu_book,
                          size: 20,
                          color: Theme.of(menuCtx).colorScheme.onSurface,
                        ),
                        const SizedBox(width: 10),
                        const Text('Správa učebníc'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'theme',
                    child: Row(
                      children: [
                        Icon(
                          Icons.format_paint,
                          size: 20,
                          color: Theme.of(menuCtx).colorScheme.onSurface,
                        ),
                        const SizedBox(width: 10),
                        const Text('Motív'),
                      ],
                    ),
                  ),
                ],
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
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 20,
                  childAspectRatio: 0.8,
                  crossAxisSpacing: 20,
                ),
                itemBuilder: (gridCtx, i) {
                  final book = books[i];
                  final cover = (book['coverImage']?.isNotEmpty ?? false)
                      ? book['coverImage']
                      : 'assets/images/logo/Logo.png';

                  return FutureBuilder<ImageInfo>(
                    future: loadImageInfo(cover),
                    builder: (tileCtx, img) {
                      if (!img.hasData) return const SizedBox.shrink();

                      return GestureDetector(
                        onTap: () {
                          tileCtx.go('/chapters', extra: {'textbook': book});
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(tileCtx).colorScheme.onSurface,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(13),
                            image: DecorationImage(
                              image:
                                  cover is String &&
                                      !cover.startsWith('assets/') &&
                                      io.File(cover).existsSync()
                                  ? FileImage(io.File(cover)) as ImageProvider
                                  : AssetImage(cover),
                              fit: BoxFit.cover,
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

// Dialóg pre správu importovaných učebníc
class _ImportedManagerDialog extends StatefulWidget {
  const _ImportedManagerDialog();

  @override
  State<_ImportedManagerDialog> createState() => _ImportedManagerDialogState();
}

class _ImportedManagerDialogState extends State<_ImportedManagerDialog> {
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
