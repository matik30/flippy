import 'package:flutter/material.dart';
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
import 'package:flippy/theme/fonts.dart';

class ScanDialog extends StatefulWidget {
  const ScanDialog({super.key});

  @override
  State<ScanDialog> createState() => _ScanDialogState();
}

class _ScanDialogState extends State<ScanDialog> {
  String? result;

  Future<void> _scan() async {
    final scanResult = await FlutterBarcodeScanner.scanBarcode(
      '#ff6666',
      'Zrušiť',
      true,
      ScanMode.QR,
    );

    if (scanResult == '-1') return;

    setState(() {
      result = scanResult;
    });
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
            Text('Scan učebnice', style: AppTextStyles.chapter),
            const SizedBox(height: 20),

            Text(
              result ?? 'Naskenuj QR kód.',
              style: AppTextStyles.body,
            ),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: _scan,
              child: const Text('Spustiť skener'),
            ),

            const SizedBox(height: 10),

            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Zavrieť'),
            ),
          ],
        ),
      ),
    );
  }
}
