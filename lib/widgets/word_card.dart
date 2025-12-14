import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
//import 'package:flippy/theme/colors.dart';
//import 'package:flippy/theme/fonts.dart';

class WordImage extends StatelessWidget {
  final String assetPath;
  final String fallbackText;
  final double? maxHeight;

  const WordImage({
    super.key,
    required this.assetPath,
    required this.fallbackText,
    this.maxHeight,
  });

  Future<bool> _assetExists() async {
    try {
      await rootBundle.load(assetPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
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