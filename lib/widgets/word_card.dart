import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
//import 'package:flippy/theme/colors.dart';
//import 'package:flippy/theme/fonts.dart';

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

  bool _isNetworkImage() {
    // Check if it's a network image (starts with http:// or https://)
    return assetPath.startsWith('http://') || assetPath.startsWith('https://');
  }

  bool _isServerImage() {
    // Check if it's a server image (starts with uploads/)
    return assetPath.startsWith('uploads/');
  }

  String _resolveImagePath() {
    // If it's already a network URL, return as is
    if (_isNetworkImage()) {
      return assetPath;
    }

    // If it's a server image and baseUrl is provided, construct URL
    if (_isServerImage() && baseUrl != null && baseUrl!.isNotEmpty) {
      // Combine baseUrl with the path
      final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl;
      return '$cleanBaseUrl/$assetPath';
    }

    // If it's an asset path, return as is
    if (assetPath.startsWith('assets/')) {
      return assetPath;
    }

    // If baseDir is provided and path is relative, combine them for local files
    if (baseDir != null && baseDir!.isNotEmpty) {
      return path.join(baseDir!, assetPath);
    }

    // Otherwise return the path as is
    return assetPath;
  }

  bool _isFileImage() {
    final resolvedPath = _resolveImagePath();

    // Check if it's NOT an asset and NOT a network URL and exists as a file
    if (!resolvedPath.startsWith('assets/') && !_isNetworkImage() && !resolvedPath.startsWith('http://') && !resolvedPath.startsWith('https://')) {
      final file = io.File(resolvedPath);
      return file.existsSync();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Check if it's a network image (either direct URL or server path)
    if (_isNetworkImage() || _isServerImage()) {
      final imageUrl = _resolveImagePath();
      return Image.network(
        imageUrl,
        fit: BoxFit.contain,
        height: maxHeight,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                  : null,
            ),
          );
        },
      );
    }

    // Check if it's a file image
    if (_isFileImage()) {
      final resolvedPath = _resolveImagePath();
      return Image.file(
        io.File(resolvedPath),
        fit: BoxFit.contain,
        height: maxHeight,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }

    // Otherwise try to load as asset
    return FutureBuilder<bool>(
      future: _assetExists(),
      builder: (context, snap) {
        final exists = snap.data == true;
        if (exists) {
          return Image.asset(
            assetPath,
            fit: BoxFit.contain,
            height: maxHeight,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          );
        }
        // changed: return nothing instead of visual placeholder when asset missing
        return const SizedBox.shrink();
        },
    );
  }

  /*Widget _placeholderCard() {
        // kept for compatibility but not used by build anymore
    return Container(
      padding: const EdgeInsets.all(12),
      constraints:
          BoxConstraints(maxHeight: maxHeight ?? 320, maxWidth: 420),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.onSurface, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0,4))
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('!', style: AppTextStyles.lesson.copyWith(fontSize: 18)),
          const SizedBox(height: 8),
          Text(
            fallbackText.toUpperCase(),
            style: AppTextStyles.heading,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Icon(Icons.image_not_supported, size: 56, color: Theme.of(context).colorScheme.onSurface),
        ],
      ),
    );
  }*/
}