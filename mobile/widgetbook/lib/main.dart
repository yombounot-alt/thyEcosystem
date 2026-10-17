import 'package:flutter/material.dart';
import 'package:thy_design_system/thy_design_system.dart';
import 'package:widgetbook/widgetbook.dart';

/// Galerie du design system THY (lot L0.9) : chaque composant, réglable, en clair et en sombre.
///
///   cd mobile/widgetbook && flutter run -d chrome
///
/// Un composant ajouté à `thy_design_system` doit y avoir sa page, avec ses états importants.
void main() => runApp(const ThyWidgetbook());

class ThyWidgetbook extends StatelessWidget {
  const ThyWidgetbook({super.key});

  @override
  Widget build(BuildContext context) {
    return Widgetbook.material(
      addons: [
        MaterialThemeAddon(
          themes: [
            WidgetbookTheme(name: 'Clair', data: AppTheme.light()),
            WidgetbookTheme(name: 'Sombre', data: AppTheme.dark()),
          ],
        ),
        TextScaleAddon(min: 1, max: 2, divisions: 2),
      ],
      directories: [
        WidgetbookFolder(
          name: 'Statuts',
          children: [
            WidgetbookComponent(
              name: 'ThyBadge',
              useCases: [
                WidgetbookUseCase(
                  name: 'Réglable',
                  builder: (context) => _center(
                    ThyBadge(
                      label: context.knobs.string(label: 'Libellé', initialValue: 'Payé'),
                      tone: _tone(context, ThyTone.success),
                      icon: context.knobs.boolean(label: 'Icône') ? Icons.check : null,
                    ),
                  ),
                ),
                WidgetbookUseCase(
                  name: 'Tous les tons',
                  builder: (context) => _center(
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tone in ThyTone.values)
                          ThyBadge(label: _toneLabels[tone]!, tone: tone),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            WidgetbookComponent(
              name: 'VerifiedBadge',
              useCases: [
                WidgetbookUseCase(
                  name: 'Numéro vérifié',
                  builder: (context) =>
                      _center(const VerifiedBadge(semanticLabel: 'Numéro de téléphone vérifié')),
                ),
              ],
            ),
          ],
        ),
        WidgetbookFolder(
          name: 'Messages',
          children: [
            WidgetbookComponent(
              name: 'ThyBanner',
              useCases: [
                WidgetbookUseCase(
                  name: 'Réglable',
                  builder: (context) => Align(
                    alignment: Alignment.topCenter,
                    child: ThyBanner(
                      message: context.knobs.string(
                        label: 'Message',
                        initialValue: 'Hors ligne · 2 ventes enregistrées sur ce téléphone.',
                      ),
                      tone: _tone(context, ThyTone.warning),
                      icon: Icons.cloud_off_outlined,
                      busy: context.knobs.boolean(label: 'Envoi en cours'),
                      onTap: context.knobs.boolean(label: 'Cliquable', initialValue: true)
                          ? () {}
                          : null,
                      actionLabel: 'Voir',
                    ),
                  ),
                ),
              ],
            ),
            WidgetbookComponent(
              name: 'showThyToast',
              useCases: [
                WidgetbookUseCase(
                  name: 'Déclencher',
                  builder: (context) => _center(
                    Builder(
                      builder: (inner) => OutlinedButton(
                        onPressed: () => showThyToast(
                          inner,
                          'Vente enregistrée.',
                          tone: _tone(context, ThyTone.success),
                        ),
                        child: const Text('Afficher le message'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        WidgetbookFolder(
          name: 'États d\'écran',
          children: [
            WidgetbookComponent(
              name: 'EmptyState',
              useCases: [
                WidgetbookUseCase(
                  name: 'Avec action',
                  builder: (context) => EmptyState(
                    icon: Icons.inventory_2_outlined,
                    message: 'Aucun produit pour l\'instant.',
                    actionLabel: 'Ajouter un produit',
                    onAction: () {},
                  ),
                ),
                WidgetbookUseCase(
                  name: 'Sans action',
                  builder: (context) => const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    message: 'Aucune vente aujourd\'hui.',
                  ),
                ),
              ],
            ),
            WidgetbookComponent(
              name: 'ErrorRetry',
              useCases: [
                WidgetbookUseCase(
                  name: 'Réessayer',
                  builder: (context) => ErrorRetry(
                    message: 'Connexion impossible. Vérifiez le réseau.',
                    onRetry: () {},
                  ),
                ),
              ],
            ),
            WidgetbookComponent(
              name: 'LoadingState',
              useCases: [
                WidgetbookUseCase(
                  name: 'Avec message',
                  builder: (context) => LoadingState(
                    message: context.knobs.stringOrNull(
                      label: 'Message',
                      initialValue: 'Chargement des ventes…',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        WidgetbookFolder(
          name: 'Saisie',
          children: [
            WidgetbookComponent(
              name: 'PrimaryButton',
              useCases: [
                WidgetbookUseCase(
                  name: 'Réglable',
                  builder: (context) => _center(
                    PrimaryButton(
                      label: context.knobs.string(label: 'Libellé', initialValue: 'Encaisser'),
                      loading: context.knobs.boolean(label: 'Chargement'),
                      onPressed: context.knobs.boolean(label: 'Actif', initialValue: true)
                          ? () {}
                          : null,
                    ),
                  ),
                ),
              ],
            ),
            WidgetbookComponent(
              name: 'AppTextField',
              useCases: [
                WidgetbookUseCase(
                  name: 'Téléphone',
                  builder: (context) => _center(
                    AppTextField(
                      controller: TextEditingController(),
                      label: 'Numéro de téléphone',
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

const _toneLabels = {
  ThyTone.neutral: 'Neutre',
  ThyTone.info: 'Info',
  ThyTone.success: 'Succès',
  ThyTone.warning: 'Attention',
  ThyTone.danger: 'Danger',
};

ThyTone _tone(BuildContext context, ThyTone initial) => context.knobs.object.dropdown<ThyTone>(
  label: 'Ton',
  options: ThyTone.values,
  initialOption: initial,
  labelBuilder: (tone) => _toneLabels[tone]!,
);

Widget _center(Widget child) => Center(
  child: Padding(padding: const EdgeInsets.all(24), child: child),
);
