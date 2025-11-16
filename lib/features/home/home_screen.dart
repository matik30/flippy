import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flippy/theme/colors.dart';
import 'package:flippy/theme/fonts.dart';

/// Pomocná funkcia – načíta metadáta asset obrázka a vráti ImageInfo.
Future<ImageInfo> _loadImageInfo(String assetPath) async {
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

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final books = [
      'assets/images/book1.jpg',
      'assets/images/book2.jpg',
      'assets/images/book3.jpg',
      'assets/images/book4.jpg',
      'assets/images/book5.jpg',
    ];

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.accent, // horná farba
              AppColors.background, // dolná farba
            ],
            stops: [0.0, 0.15], // začína sa od 85% a končí na 100%
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

          body: GridView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: books.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 20,
              crossAxisSpacing: 20,
            ),
            itemBuilder: (_, i) {
              return FutureBuilder<ImageInfo>(
                future: _loadImageInfo(books[i]),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const SizedBox.shrink();
                  }

                  final imageInfo = snapshot.data!;
                  final width = imageInfo.image.width.toDouble();
                  final height = imageInfo.image.height.toDouble();
                  final aspect = width / height;

                  return GestureDetector(
                    onTap: () {
                      context.go('/chapters', extra: i);
                    },
                    child: AspectRatio(
                      aspectRatio: aspect,
                      child: Container(
                        height: 200,
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.text, width: 2),
                          borderRadius: BorderRadius.circular(13),
                          image: DecorationImage(
                            image: AssetImage(books[i]),
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
          ),
        ),
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/scan'),
        backgroundColor: AppColors.primary,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
