import 'package:flutter/material.dart';

import 'tone.dart';

/// Bandeau d'information pleine largeur, en haut d'un écran : hors ligne, données à envoyer,
/// compte suspendu… Annoncé par les lecteurs d'écran quand il apparaît ou change.
class ThyBanner extends StatelessWidget {
  const ThyBanner({
    super.key,
    required this.message,
    this.tone = ThyTone.info,
    this.icon,
    this.busy = false,
    this.onTap,
    this.actionLabel,
  });

  final String message;
  final ThyTone tone;
  final IconData? icon;

  /// Une opération est en cours : un indicateur de progression remplace l'icône.
  final bool busy;

  /// Le bandeau entier est cliquable (par exemple : ouvrir la liste des ventes en attente).
  final VoidCallback? onTap;

  /// Libellé affiché à droite quand [onTap] est fourni (par exemple « Voir »).
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final colors = toneColors(context, tone);
    final text = Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.foreground);
    return Semantics(
      container: true,
      liveRegion: true,
      button: onTap != null,
      child: Material(
        color: colors.background,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                if (busy)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: colors.foreground),
                  )
                else if (icon != null)
                  Icon(icon, size: 20, color: colors.foreground),
                if (busy || icon != null) const SizedBox(width: 12),
                Expanded(child: Text(message, style: text)),
                if (onTap != null && actionLabel != null) ...[
                  const SizedBox(width: 8),
                  Text(actionLabel!, style: text?.copyWith(fontWeight: FontWeight.w600)),
                  Icon(Icons.chevron_right, size: 20, color: colors.foreground),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
