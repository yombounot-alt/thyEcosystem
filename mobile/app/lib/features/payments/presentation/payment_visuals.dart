import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thy_design_system/thy_design_system.dart';

import '../application/payments_providers.dart';
import '../data/payment_method_models.dart';
import '../data/payment_models.dart';

/// The colour and icon that stand for a kind of payment when the owner has not uploaded a logo.
/// Deliberately generic: no operator's brand is reproduced here — the owner can upload a real logo.
/// Colours come from the theme ([ThyColors]) so they stay readable in light and dark mode.
({Color color, IconData icon}) providerVisual(String provider, ThyColors c) {
  switch (provider) {
    case PaymentProvider.orangeMoney:
      return (color: c.accentText, icon: Icons.phone_android);
    case PaymentProvider.mobileMoney:
      return (color: c.success, icon: Icons.smartphone);
    case PaymentProvider.merchantCode:
      return (color: c.primary, icon: Icons.storefront_outlined);
    default:
      return (color: c.onSurfaceMuted, icon: Icons.account_balance_wallet_outlined);
  }
}

/// The owner's logo for an option, or the icon of its kind.
class PaymentOptionLogo extends ConsumerWidget {
  const PaymentOptionLogo({
    super.key,
    required this.optionId,
    required this.provider,
    required this.hasLogo,
    this.size = 48,
  });

  final String? optionId;
  final String provider;
  final bool hasLogo;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visual = providerVisual(provider, context.colors);
    final id = optionId;
    final bytes = hasLogo && id != null ? ref.watch(paymentLogoProvider(id)).value : null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 4),
      child: SizedBox(
        width: size,
        height: size,
        child:
            bytes == null
                ? ColoredBox(
                  color: visual.color.withValues(alpha: 0.14),
                  child: Icon(visual.icon, color: visual.color, size: size * 0.55),
                )
                // Logos are pictures made for a white background, in both themes.
                : ColoredBox(
                  color: ThyPalette.slateWhite,
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Icon(visual.icon, color: visual.color),
                  ),
                ),
      ),
    );
  }
}

Color statusColor(String status, ThyColors c) {
  switch (status) {
    case PaymentStatus.pending:
      return c.warning;
    case PaymentStatus.submitted:
      return c.info;
    case PaymentStatus.verified:
      return c.success;
    case PaymentStatus.rejected:
      return c.danger;
    default:
      return c.onSurfaceMuted; // cancelled
  }
}

/// 🟠 En attente · 🔵 Vérification en cours · 🟢 Payé · 🔴 Refusé · ⚪ Annulé
class PaymentStatusBadge extends StatelessWidget {
  const PaymentStatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status, context.colors);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 9, color: color),
          const SizedBox(width: 6),
          Text(
            PaymentStatus.label(status),
            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}
