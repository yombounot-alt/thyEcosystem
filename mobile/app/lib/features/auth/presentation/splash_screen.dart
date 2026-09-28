import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../application/auth_controller.dart';
import '../application/auth_state.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreachable =
        ref.watch(authControllerProvider.select((s) => s.status)) == AuthStatus.unreachable;

    return Scaffold(
      // Moment de marque (charte §2.1) : marine dans les deux modes, texte blanc à 13,4:1.
      backgroundColor: ThyPalette.blue900,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'THY Business',
                style: TextStyle(
                  color: ThyPalette.slateWhite,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 24),
              if (!unreachable)
                const CircularProgressIndicator(color: ThyPalette.slateWhite)
              else ...[
                const Icon(Icons.cloud_off_outlined, color: ThyPalette.slateWhite, size: 40),
                const SizedBox(height: 12),
                const Text(
                  'Impossible de joindre le serveur.\nVous restez connecté : réessayez dès que le réseau est de retour.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ThyPalette.slateWhite),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: ThyPalette.slateWhite,
                    foregroundColor: ThyPalette.blue900,
                  ),
                  onPressed: () => ref.read(authControllerProvider.notifier).retry(),
                  child: const Text('Réessayer'),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: ThyPalette.slateWhite),
                  onPressed: () => ref.read(authControllerProvider.notifier).logout(),
                  child: const Text('Se déconnecter'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
