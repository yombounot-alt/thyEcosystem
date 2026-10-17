@Tags(['golden'])
library;

import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thy_design_system/thy_design_system.dart';

/// Le scénario dans le thème, sur le fond de ce thème (sans quoi le mode sombre serait trompeur).
Widget _themed(ThemeData theme, {required Widget child}) => Theme(
  data: theme,
  child: Material(
    color: theme.scaffoldBackgroundColor,
    child: Padding(padding: const EdgeInsets.all(12), child: child),
  ),
);

/// Goldens des composants, en clair et en sombre (lot L0.9). Mise à jour après un changement
/// voulu : `flutter test --update-goldens --tags golden` dans ce paquet, puis relire les images.
void main() {
  for (final (name, theme) in [('light', AppTheme.light()), ('dark', AppTheme.dark())]) {
    goldenTest(
      'composants ($name)',
      fileName: 'components_$name',
      // Les indicateurs de progression tournent sans fin : une seule image, toujours la même.
      pumpBeforeTest: pumpOnce,
      builder:
          () => GoldenTestGroup(
            columns: 2,
            scenarioConstraints: const BoxConstraints(maxWidth: 360),
            children: [
              GoldenTestScenario(
                name: 'badges',
                child: _themed(
                  theme,
                  child: const Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ThyBadge(label: 'Brouillon'),
                      ThyBadge(label: 'Info', tone: ThyTone.info),
                      ThyBadge(label: 'Payé', tone: ThyTone.success, icon: Icons.check),
                      ThyBadge(label: 'En attente', tone: ThyTone.warning),
                      ThyBadge(label: 'Refusé', tone: ThyTone.danger),
                      VerifiedBadge(),
                    ],
                  ),
                ),
              ),
              GoldenTestScenario(
                name: 'bannières',
                child: _themed(
                  theme,
                  child: const Column(
                    children: [
                      ThyBanner(
                        message: 'Hors ligne',
                        tone: ThyTone.warning,
                        icon: Icons.cloud_off,
                      ),
                      ThyBanner(message: 'Envoi…', tone: ThyTone.warning, busy: true),
                      ThyBanner(message: 'Refusée', tone: ThyTone.danger, icon: Icons.error),
                    ],
                  ),
                ),
              ),
              GoldenTestScenario(
                name: 'état vide',
                child: _themed(
                  theme,
                  child: const SizedBox(
                    height: 200,
                    child: EmptyState(icon: Icons.inbox, message: 'Aucune vente aujourd\'hui.'),
                  ),
                ),
              ),
              GoldenTestScenario(
                name: 'erreur',
                child: _themed(
                  theme,
                  child: SizedBox(
                    height: 200,
                    child: ErrorRetry(message: 'Connexion impossible.', onRetry: () {}),
                  ),
                ),
              ),
              GoldenTestScenario(
                name: 'boutons et champ',
                child: _themed(
                  theme,
                  child: Column(
                    children: [
                      PrimaryButton(label: 'Encaisser', onPressed: () {}),
                      const SizedBox(height: 8),
                      PrimaryButton(label: 'Encaisser', onPressed: () {}, loading: true),
                      const SizedBox(height: 8),
                      AppTextField(controller: TextEditingController(), label: 'Téléphone'),
                    ],
                  ),
                ),
              ),
            ],
          ),
    );
  }
}
