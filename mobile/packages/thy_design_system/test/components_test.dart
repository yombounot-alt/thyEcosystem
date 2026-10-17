import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thy_design_system/thy_design_system.dart';

Widget _host(Widget child, {ThemeData? theme}) =>
    MaterialApp(theme: theme ?? AppTheme.light(), home: Scaffold(body: child));

/// Contraste WCAG entre deux couleurs opaques.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('ThyTone', () {
    for (final (name, theme) in [('clair', AppTheme.light()), ('sombre', AppTheme.dark())]) {
      testWidgets('chaque ton tient 4,5:1 en mode $name', (tester) async {
        late BuildContext ctx;
        await tester.pumpWidget(
          _host(
            Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox();
              },
            ),
            theme: theme,
          ),
        );
        for (final tone in ThyTone.values) {
          final colors = toneColors(ctx, tone);
          expect(colors.background.a, 1, reason: '$tone : fond opaque');
          expect(
            _contrast(colors.foreground, colors.background),
            greaterThanOrEqualTo(4.5),
            reason: '$tone en mode $name',
          );
        }
      });
    }
  });

  testWidgets('VerifiedBadge annonce ce qui est vérifié', (tester) async {
    await tester.pumpWidget(_host(const VerifiedBadge(semanticLabel: 'Numéro vérifié')));
    expect(find.text('Vérifié'), findsOneWidget);
    expect(find.bySemanticsLabel('Numéro vérifié'), findsOneWidget);
  });

  testWidgets('ThyBanner : cliquable avec son action, indicateur quand occupé', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        ThyBanner(
          message: '2 ventes à envoyer.',
          tone: ThyTone.warning,
          icon: Icons.cloud_upload_outlined,
          onTap: () => taps++,
          actionLabel: 'Voir',
        ),
      ),
    );
    await tester.tap(find.text('2 ventes à envoyer.'));
    expect(taps, 1);
    expect(find.text('Voir'), findsOneWidget);

    await tester.pumpWidget(_host(const ThyBanner(message: 'Envoi…', busy: true)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Voir'), findsNothing);
  });

  testWidgets('EmptyState : action seulement si elle est fournie', (tester) async {
    var started = false;
    await tester.pumpWidget(
      _host(
        EmptyState(
          icon: Icons.inventory_2_outlined,
          message: 'Aucun produit.',
          actionLabel: 'Ajouter un produit',
          onAction: () => started = true,
        ),
      ),
    );
    await tester.tap(find.text('Ajouter un produit'));
    expect(started, isTrue);

    await tester.pumpWidget(
      _host(const EmptyState(icon: Icons.inventory_2_outlined, message: 'Aucun produit.')),
    );
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('ErrorRetry : « Réessayer » relance', (tester) async {
    var retried = 0;
    await tester.pumpWidget(_host(ErrorRetry(message: 'Hors ligne.', onRetry: () => retried++)));
    await tester.tap(find.text('Réessayer'));
    expect(retried, 1);
  });

  testWidgets('showThyToast remplace le message précédent au lieu de l\'empiler', (tester) async {
    await tester.pumpWidget(
      _host(
        Builder(
          builder:
              (context) => Column(
                children: [
                  TextButton(
                    onPressed: () => showThyToast(context, 'Premier'),
                    child: const Text('a'),
                  ),
                  TextButton(
                    onPressed: () => showThyToast(context, 'Second', tone: ThyTone.success),
                    child: const Text('b'),
                  ),
                ],
              ),
        ),
      ),
    );
    await tester.tap(find.text('a'));
    await tester.pump();
    await tester.tap(find.text('b'));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('Premier'), findsNothing);
  });
}
