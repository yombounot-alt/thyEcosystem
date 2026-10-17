import 'package:flutter/material.dart';

import 'tone.dart';

/// Pastille de statut courte (« Payé », « En attente », « Suspendu »). Le texte porte le sens :
/// la couleur ne fait que le renforcer (jamais une information portée par la couleur seule).
class ThyBadge extends StatelessWidget {
  const ThyBadge({super.key, required this.label, this.tone = ThyTone.neutral, this.icon});

  final String label;
  final ThyTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = toneColors(context, tone);
    final style = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: colors.foreground, fontWeight: FontWeight.w600);
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.background, borderRadius: BorderRadius.circular(999)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: colors.foreground),
              const SizedBox(width: 4),
            ],
            Text(label, style: style),
          ],
        ),
      ),
    );
  }
}

/// Signale qu'une information a été vérifiée par THY (numéro de téléphone, entreprise…). Lu par
/// les lecteurs d'écran avec ce qui a été vérifié.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.label = 'Vérifié', this.semanticLabel});

  final String label;

  /// Ce que le lecteur d'écran annonce, par exemple « Numéro vérifié ». Par défaut : [label].
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: ThyBadge(label: label, tone: ThyTone.info, icon: Icons.verified),
    );
  }
}
