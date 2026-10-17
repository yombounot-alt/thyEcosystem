import 'dart:async';

import 'package:alchemist/alchemist.dart';

/// Goldens « CI » seulement : le texte est remplacé par des blocs et les ombres sont désactivées,
/// donc l'image est la même sous Windows, macOS et Linux. Les goldens « plateforme » (vrai texte)
/// différeraient d'un poste à l'autre : ils sont désactivés.
Future<void> testExecutable(FutureOr<void> Function() testMain) {
  return AlchemistConfig.runWithConfig(
    config: const AlchemistConfig(
      platformGoldensConfig: PlatformGoldensConfig(enabled: false),
      ciGoldensConfig: CiGoldensConfig(enabled: true),
    ),
    run: () async => testMain(),
  );
}
