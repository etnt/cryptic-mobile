/// QR Scanner screen for enrollment.
///
/// Uses the device camera to scan an enrollment QR code.
/// On simulators (no camera), provides a text-paste fallback.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../providers/enrollment_provider.dart';

/// Screen that displays the camera viewfinder for QR code scanning.
class QrScannerScreen extends ConsumerStatefulWidget {
  const QrScannerScreen({super.key});

  @override
  ConsumerState<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends ConsumerState<QrScannerScreen> {
  MobileScannerController? _controller;
  bool _scanned = false;
  bool _cameraFailed = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final ctrl = MobileScannerController(
        formats: [BarcodeFormat.qrCode],
      );
      await ctrl.start();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      ctrl.barcodes.listen(_onDetect);
      setState(() => _controller = ctrl);
    } catch (_) {
      if (mounted) setState(() => _cameraFailed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    setState(() => _scanned = true);
    ref.read(enrollmentProvider.notifier).onQrScanned(barcode.rawValue!);
  }

  Future<void> _pasteQrData() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clipboard is empty')),
        );
      }
      return;
    }
    ref.read(enrollmentProvider.notifier).onQrScanned(text);
  }

  void _showManualEntryDialog() {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste QR Data'),
        content: TextField(
          controller: controller,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: 'Paste the enrollment JSON here…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              Navigator.pop(ctx);
              if (text.isNotEmpty) {
                ref.read(enrollmentProvider.notifier).onQrScanned(text);
              }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Enrollment QR'),
        actions: [
          IconButton(
            icon: const Icon(Icons.content_paste),
            tooltip: 'Paste QR data',
            onPressed: _pasteQrData,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _cameraFailed
                ? _buildNoCameraFallback(theme)
                : (_controller != null
                    ? MobileScanner(
                        controller: _controller!,
                        errorBuilder: (_, __) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted && !_cameraFailed) {
                              setState(() => _cameraFailed = true);
                            }
                          });
                          return _buildNoCameraFallback(theme);
                        },
                      )
                    : const Center(child: CircularProgressIndicator())),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _cameraFailed
                  ? 'No camera available.\n'
                      'Paste the enrollment QR data using the button above\n'
                      'or tap "Enter Manually" below.'
                  : 'Point your camera at the enrollment QR code\n'
                      'provided by your administrator.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoCameraFallback(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.qr_code_2,
              size: 80,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 24),
            Text(
              'Camera not available',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Running on simulator or no camera permission.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _pasteQrData,
              icon: const Icon(Icons.content_paste),
              label: const Text('Paste from Clipboard'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _showManualEntryDialog,
              icon: const Icon(Icons.edit_note),
              label: const Text('Enter Manually'),
            ),
          ],
        ),
      ),
    );
  }
}
