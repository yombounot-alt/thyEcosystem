import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_theme.dart';
import 'scan_types.dart';

/// Product barcodes (what shops sell) plus QR codes, for shops that print their own labels.
const _formats = [
  BarcodeFormat.ean13,
  BarcodeFormat.ean8,
  BarcodeFormat.upcA,
  BarcodeFormat.upcE,
  BarcodeFormat.code128,
  BarcodeFormat.code39,
  BarcodeFormat.code93,
  BarcodeFormat.itf14,
  BarcodeFormat.qrCode,
];

/// Full-screen camera that reads barcodes. Kept thin: what a code *means* is the caller's business
/// ([onCode]); this screen only reads, debounces, and shows the answer.
class BarcodeScanScreen extends StatefulWidget {
  const BarcodeScanScreen({
    super.key,
    required this.onCode,
    required this.continuous,
    required this.title,
  });

  final ScanHandler onCode;
  final bool continuous;
  final String title;

  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<BarcodeScanScreen> {
  final _controller = MobileScannerController(formats: _formats, facing: CameraFacing.back);
  final _debouncer = ScanDebouncer();

  ScanFeedback? _feedback;
  bool _busy = false;
  bool _closing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy || _closing) return;

    final code =
        capture.barcodes
            .map((b) => b.rawValue)
            .whereType<String>()
            .where((c) => c.trim().isNotEmpty)
            .firstOrNull;
    if (code == null || !_debouncer.accept(code)) return;

    _busy = true;
    try {
      final feedback = await widget.onCode(code.trim());
      if (feedback.isProblem) {
        HapticFeedback.heavyImpact();
      } else {
        HapticFeedback.mediumImpact();
      }
      if (!mounted) return;
      if (!widget.continuous) {
        _closing = true;
        Navigator.of(context).pop();
        return;
      }
      setState(() => _feedback = feedback);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final feedback = _feedback;

    return Scaffold(
      backgroundColor: Colors.black,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        // The top of the picture is darkened below, so the status bar icons go light.
        value: SystemUiOverlayStyle.light,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              // The camera takes a moment to start (several seconds on a slow phone or an emulator).
              placeholderBuilder:
                  (context) => const ColoredBox(
                    color: Colors.black,
                    child: Center(child: CircularProgressIndicator(color: Colors.white)),
                  ),
              errorBuilder:
                  (context, error) =>
                      _CameraProblem(error: error, onRetry: () => _controller.start()),
              overlayBuilder: (context, constraints) => const _AimFrame(),
            ),
            // White title and buttons vanish over a bright scene (a white label, a wall): darken the top.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: MediaQuery.paddingOf(context).top + 72,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          tooltip: 'Fermer',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        Expanded(
                          child: Text(
                            widget.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        ValueListenableBuilder(
                          valueListenable: _controller,
                          builder: (context, state, _) {
                            if (state.torchState == TorchState.unavailable) {
                              return const SizedBox.shrink();
                            }
                            final on = state.torchState == TorchState.on;
                            return IconButton(
                              icon: Icon(
                                on ? Icons.flash_on : Icons.flash_off,
                                color: on ? Colors.amber : Colors.white,
                              ),
                              tooltip: on ? 'Éteindre la lampe' : 'Allumer la lampe',
                              onPressed: () => _controller.toggleTorch(),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    decoration: const BoxDecoration(
                      color: Color(0xCC000000),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (feedback != null)
                          Row(
                            children: [
                              Icon(
                                feedback.isProblem ? Icons.error_outline : Icons.check_circle,
                                color: feedback.isProblem ? AppColors.danger : AppColors.success,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  feedback.message,
                                  style: const TextStyle(color: Colors.white, fontSize: 16),
                                ),
                              ),
                            ],
                          )
                        else
                          // No point telling people to aim when the camera itself is not running.
                          ValueListenableBuilder(
                            valueListenable: _controller,
                            builder:
                                (context, state, _) =>
                                    state.error != null
                                        ? const SizedBox.shrink()
                                        : const Text(
                                          'Placez le code-barres dans le cadre.',
                                          style: TextStyle(color: Colors.white70, fontSize: 15),
                                        ),
                          ),
                        if (widget.continuous) ...[
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Terminer'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A frame to aim with; purely visual.
class _AimFrame extends StatelessWidget {
  const _AimFrame();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: MediaQuery.sizeOf(context).width * 0.78,
        height: 170,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white, width: 2.5),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

/// Says what is wrong (mostly: the camera permission) instead of leaving a black screen.
class _CameraProblem extends StatelessWidget {
  const _CameraProblem({required this.error, required this.onRetry});

  final MobileScannerException error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    final unsupported = error.errorCode == MobileScannerErrorCode.unsupported;

    final String message;
    if (denied) {
      message =
          "L'accès à la caméra est refusé.\nAutorisez-le dans les réglages du téléphone "
          '(Applications → THY Business → Autorisations), puis réessayez.';
    } else if (unsupported) {
      message =
          'Ce téléphone ne peut pas scanner avec la caméra.\nUtilisez la recherche ou une douchette.';
    } else {
      message = "La caméra n'a pas pu démarrer. Réessayez.";
    }

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, color: Colors.white, size: 48),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              if (!unsupported) ...[
                const SizedBox(height: 20),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                  onPressed: onRetry,
                  child: const Text('Réessayer'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
