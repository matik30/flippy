import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:cached_network_image/cached_network_image.dart';

class WordImage extends StatelessWidget {
  final String assetPath;
  final String fallbackText;
  final double? maxHeight;
  final String? baseDir; // Base directory for relative image paths
  final String? baseUrl; // Base URL for server images

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

  Future<String?> _detectImageSource() async {
    // 1) direct network URL
    if (assetPath.startsWith('http://') || assetPath.startsWith('https://')) {
      return assetPath;
    }

    // 2) server-relative path (uploads/) and baseUrl provided
    if (assetPath.startsWith('uploads/') &&
        baseUrl != null &&
        baseUrl!.isNotEmpty) {
      return _buildServerUrl();
    }

    // 3) local file (baseDir provided or direct path) - check asynchronously
    if (baseDir != null && baseDir!.isNotEmpty) {
      final resolved = path.join(baseDir!, assetPath);
      if (await _fileExists(resolved)) return 'file:$resolved';
    } else {
      // if assetPath looks like a filesystem path, try it
      if (assetPath.contains('/') || assetPath.contains('\\')) {
        final resolved = assetPath;
        if (await _fileExists(resolved)) return 'file:$resolved';
      }
    }

    // 4) asset bundled with app
    if (assetPath.startsWith('assets/') && await _assetExists()) {
      return 'asset:$assetPath';
    }

    // none found
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _detectImageSource(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          // avoid blocking layout; show small loader
          return SizedBox(
            height: maxHeight ?? 120,
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        final src = snap.data;
        if (src == null) {
          // no image available
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
