import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final MobileScannerController _cameraController = MobileScannerController();
  bool _handling = false;

  Future<String?> _handleQr(String raw) async {
    try {
      final uri = Uri.parse(raw);
      final response = await http.get(uri);

      if (response.statusCode != 200) {
        return 'Server vrátil ${response.statusCode}';
      }

      jsonDecode(response.body);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('textbook_json', response.body);

      return null;
    } catch (e) {
      return 'Chyba pri spracovaní QR/JSON: $e';
    }
  }

  void _onDetect(Barcode barcode) {
    final raw = barcode.rawValue;
    if (raw == null || _handling) return;

    _handling = true;
    _processQr(raw);
  }

  Future<void> _processQr(String raw) async {
    await _cameraController.stop();
    if (!mounted) return;

    final result = await showDialog<_QrResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _QrProcessingDialog(
        raw: raw,
        handleQr: _handleQr,
      ),
    );

    if (!mounted) return;

    if (result == _QrResult.success) {
      GoRouter.of(context).go('/?r=${DateTime.now().millisecondsSinceEpoch}');
    } else {
      await _cameraController.start();
    }

    _handling = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Naskenuj QR učebnice'),
      ),
      body: MobileScanner(
        controller: _cameraController,
        onDetect: (barcode, _) => _onDetect(barcode),
      ),
    );
  }
}

enum _QrResult { success, error }

class _QrProcessingDialog extends StatefulWidget {
  final String raw;
  final Future<String?> Function(String) handleQr;

  const _QrProcessingDialog({
    required this.raw,
    required this.handleQr,
  });

  @override
  State<_QrProcessingDialog> createState() => _QrProcessingDialogState();
}

class _QrProcessingDialogState extends State<_QrProcessingDialog> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final err = await widget.handleQr(widget.raw);
    if (!mounted) return;

    setState(() {
      _loading = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: _loading
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  SizedBox(height: 24),
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text('Načítavam...'),
                  SizedBox(height: 16),
                ],
              )
            : _error == null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 24),
                      const Icon(Icons.check_circle,
                          size: 64, color: Colors.green),
                      const SizedBox(height: 20),
                      const Text(
                        'Kniha bola pridaná',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop(_QrResult.success);
                        },
                        child: const Text('Zavrieť'),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 24),
                      const Icon(Icons.error,
                          size: 64, color: Colors.red),
                      const SizedBox(height: 20),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () =>
                            Navigator.of(context).pop(_QrResult.error),
                        child: const Text('Skúsiť znova'),
                      ),
                    ],
                  ),
      ),
    );
  }
}
