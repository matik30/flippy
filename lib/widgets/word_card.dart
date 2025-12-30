// Komponenta WordImage zobrazuje obrázok slovíčka z rôznych zdrojov
// (sieť, súbor alebo asset). Detekuje dostupný zdroj a renderuje vhodný widget.

import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:cached_network_image/cached_network_image.dart';

class WordImage extends StatelessWidget {
  final String assetPath;
  final String fallbackText;
  final double? maxHeight;
  final String? baseDir; // základný adresár pre relatívne cesty k obrázkom
  final String? baseUrl; // základná URL pre obrázky na serveri

  const WordImage({
    super.key,
    required this.assetPath,
    required this.fallbackText,
    this.maxHeight,
    this.baseDir,
    this.baseUrl,
  });

  Future<bool> _assetExists() async {
    try {
      await rootBundle.load(assetPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _fileExists(String p) async {
    try {
      final file = io.File(p);
      return await file.exists();
    } catch (_) {
      return false;
    }
  }

  String _buildServerUrl() {
    final cleanBaseUrl = baseUrl!.endsWith('/')
        ? baseUrl!.substring(0, baseUrl!.length - 1)
        : baseUrl!;
    return '$cleanBaseUrl/$assetPath';
  }

  // Zistí zdroj obrázka (http, server-relative, lokálny súbor alebo asset)
  Future<String?> _detectImageSource() async {
    // 1) priamy sieťový URL
    if (assetPath.startsWith('http://') || assetPath.startsWith('https://')) {
      return assetPath;
    }

    // 2) relatívna cesta na serveri (uploads/) a poskytnuté baseUrl
    if (assetPath.startsWith('uploads/') &&
        baseUrl != null &&
        baseUrl!.isNotEmpty) {
      return _buildServerUrl();
    }

    // 3) lokálny súbor (baseDir poskytnutý alebo priamy cestný) - kontrola asynchrónne
    if (baseDir != null && baseDir!.isNotEmpty) {
      final resolved = path.join(baseDir!, assetPath);
      if (await _fileExists(resolved)) return 'file:$resolved';
    } else {
      // priama cesta na súbor
      if (assetPath.contains('/') || assetPath.contains('\\')) {
        final resolved = assetPath;
        if (await _fileExists(resolved)) return 'file:$resolved';
      }
    }

    // 4) asset v balíku
    if (assetPath.startsWith('assets/') && await _assetExists()) {
      return 'asset:$assetPath';
    }

    // žiadny zdroj nenájdený
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Slovensky: V build metóde sa čaká na detekciu zdroja a potom sa zobrazí príslušný widget
    // (CachedNetworkImage, Image.file alebo Image.asset).
    return FutureBuilder<String?>(
      future: _detectImageSource(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          // čakanie na detekciu zdroja
          return SizedBox(
            height: maxHeight ?? 120,
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        final src = snap.data;
        if (src == null) {
          // žiadny obrázok k dispozícii
          return const SizedBox.shrink();
        }

        if (src.startsWith('http://') || src.startsWith('https://')) {
          return CachedNetworkImage(
            imageUrl: src,
            fit: BoxFit.contain,
            height: maxHeight,
            placeholder: (ctx, url) => SizedBox(
              height: maxHeight ?? 120,
              child: const Center(child: CircularProgressIndicator()),
            ),
            errorWidget: (ctx, url, err) => const SizedBox.shrink(),
          );
        }

        if (src.startsWith('file:')) {
          final filePath = src.substring(5);
          return Image.file(
            io.File(filePath),
            fit: BoxFit.contain,
            height: maxHeight,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          );
        }

        if (src.startsWith('asset:')) {
          final asset = src.substring(6);
          return Image.asset(
            asset,
            fit: BoxFit.contain,
            height: maxHeight,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }
}
