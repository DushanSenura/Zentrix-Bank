import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Builds the live camera view that reports each QR code it reads. A provider holds this so tests can swap in a fake
/// (a camera can't run under `flutter test`).
typedef QrScannerBuilder = Widget Function(BuildContext context, ValueChanged<String> onCode);

Widget cameraQrScanner(BuildContext context, ValueChanged<String> onCode) => CameraQrScanner(onCode: onCode);

class CameraQrScanner extends StatefulWidget {
  const CameraQrScanner({super.key, required this.onCode});
  final ValueChanged<String> onCode;

  @override
  State<CameraQrScanner> createState() => _CameraQrScannerState();
}

class _CameraQrScannerState extends State<CameraQrScanner> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode], detectionSpeed: DetectionSpeed.noDuplicates);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Camera view. Point it at a QR code to scan it.',
    child: MobileScanner(
      controller: _controller,
      onDetect: (capture) {
        for (final b in capture.barcodes) {
          final value = b.rawValue;
          if (value != null && value.isNotEmpty) {
            widget.onCode(value);
            return;
          }
        }
      },
      errorBuilder: (context, error) {
        final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
        return _CameraProblem(
          message: denied
              ? 'Camera access is off. Allow it for Zentrix Bank in Settings to scan, or choose a sample code below.'
              : 'The camera isn’t available right now. You can choose a sample code below.',
        );
      },
    ),
  );
}

class _CameraProblem extends StatelessWidget {
  const _CameraProblem({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.no_photography_rounded, size: 40, color: c.textSecondary),
              const SizedBox(height: 8),
              Text(message, style: AppTypography.bodySmall.copyWith(color: c.textSecondary), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
