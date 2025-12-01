import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flippy/theme/colors.dart';
import 'package:flippy/theme/fonts.dart';
import 'package:flippy/widgets/scan_dialog.dart';
import 'package:flutter/foundation.dart';

Future<List<String>> loadJsonPaths() async {
  debugPrint("loadJsonPaths() CALLED");

  // try engine-provided manifest (may not exist on desktop -> throws)
  try {
    // Read the generated AssetManifest.json and decode it to a Map
    final manifestContent = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifestMap = await compute(jsonDecode, manifestContent) as Map<String,dynamic>;
    //final Map<String, dynamic> manifestMap = json.decode(manifestContent);

    // Vyfiltruj JSON súbory z assets/data/
    final files = manifestMap.keys
        .where(
          (path) => path.startsWith('assets/data/') && path.endsWith('.json'),
        )
        .cast<String>()
        .toList();

    debugPrint("FOUND JSON FILES (from AssetManifest.json): $files");
    return files;
  } catch (e) {
    debugPrint("AssetManifest.json not available: $e");

    // fallback: try a local index you add to assets/data/index.json
    try {
      final indexContent = await rootBundle.loadString('assets/data/index.json');
      final List<dynamic> list = json.decode(indexContent) as List<dynamic>;
      final files = list.cast<String>().where((p) => p.endsWith('.json')).toList();
      debugPrint("FOUND JSON FILES (from assets/data/index.json): $files");
      return files;
    } catch (e2) {
      debugPrint("index.json fallback failed: $e2");

      // final fallback: probe a small list of expected files so UI doesn't hang
      final candidates = ['assets/data/project1.json', 'assets/data/project2.json'];
      final found = <String>[];
      for (final p in candidates) {
        try {
          await rootBundle.loadString(p);
          found.add(p);
        } catch (_) {}
      }
      debugPrint("FOUND JSON FILES (fallback candidates): $found");
      return found;
    }
  }
}

/// Načíta textbook objekt z jedného JSON
Future<Map<String, dynamic>> loadTextbook(String path) async {
  final jsonString = await rootBundle.loadString(path);
  final jsonData = jsonDecode(jsonString);
  return jsonData["textbook"];
}

/// Načíta image info pre aspect ratio
Future<ImageInfo> loadImageInfo(String assetPath) async {
  final imageProvider = AssetImage(assetPath);
  final config = const ImageConfiguration();
  final completer = Completer<ImageInfo>();

  final stream = imageProvider.resolve(config);
  late final ImageStreamListener listener;

  listener = ImageStreamListener(
    (ImageInfo info, bool _) {
      completer.complete(info);
      stream.removeListener(listener);
    },
    onError: (error, stack) {
      completer.completeError(error);
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
  late final Future<List<String>> _jsonPathsFuture;

  @override
  void initState() {
    super.initState();
    _jsonPathsFuture = loadJsonPaths();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            centerTitle: true,
            title: Text('Učebnice', style: AppTextStyles.chapter),
          ),

          body: FutureBuilder<List<String>>(
            future: _jsonPathsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                debugPrint('loadJsonPaths error: ${snapshot.error}');
                return Center(child: Text('Error loading assets'));
              }
              final jsonPaths = snapshot.data ?? [];
              if (jsonPaths.isEmpty) {
                return Center(
                  child: Text(
                    'No json files found in assets/data/ (check pubspec.yaml)',
                  ),
                );
              }

              return FutureBuilder<List<Map<String, dynamic>>>(
                future: Future.wait(jsonPaths.map(loadTextbook)),
                builder: (context, snapshot2) {
                  if (!snapshot2.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final textbooks = snapshot2.data!;

                  return GridView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: textbooks.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 20,
                          crossAxisSpacing: 20,
                        ),
                    itemBuilder: (_, index) {
                      final book = textbooks[index];
                      final cover = book["coverImage"];

                      return FutureBuilder<ImageInfo>(
                        future: loadImageInfo(cover),
                        builder: (context, img) {
                          if (!img.hasData) {
                            return const SizedBox.shrink();
                          }

                          final imageInfo = img.data!;
                          final aspect =
                              imageInfo.image.width / imageInfo.image.height;

                          return GestureDetector(
                            onTap: () {
                              context.go('/chapters', extra: book);
                            },
                            child: AspectRatio(
                              aspectRatio: aspect,
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: AppColors.text,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(13),
                                  image: DecorationImage(
                                    image: AssetImage(cover),
                                    fit: BoxFit.cover,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 8,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showDialog(context: context, builder: (_) => const ScanDialog());
        },
        backgroundColor: AppColors.primary,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
