import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thy_core/thy_core.dart';

import 'fakes.dart';

Future<void> openMyPlan(WidgetTester tester) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Plus')));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Mon offre'));
  await tester.tap(find.text('Mon offre'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('"Mon offre" shows the plan, each limit with its usage, and what is not included', (
    tester,
  ) async {
    await pumpAuthenticatedApp(tester, subscription: FakeSubscriptionApi(members: 2, products: 12));
    await openMyPlan(tester);

    expect(find.text('Offre Gratuit'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget); // team
    expect(find.text('12 / 50'), findsOneWidget); // products
    expect(find.text('Export des rapports'), findsOneWidget);
    expect(find.text('Non inclus'), findsOneWidget);
    expect(find.text('Limite atteinte'), findsNothing);
  });

  testWidgets('a full limit is flagged, an unlimited one says so', (tester) async {
    await pumpAuthenticatedApp(
      tester,
      subscription: FakeSubscriptionApi(members: 3, products: 7, productLimit: null),
    );
    await openMyPlan(tester);

    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.text('Limite atteinte'), findsOneWidget);
    expect(find.text('7 · illimité'), findsOneWidget);
  });

  testWidgets('an expired plan explains that the free limits apply and nothing is lost', (
    tester,
  ) async {
    await pumpAuthenticatedApp(tester, subscription: FakeSubscriptionApi(status: 'EXPIRED'));
    await openMyPlan(tester);

    expect(find.text('Expirée'), findsOneWidget);
    expect(find.textContaining("les limites de l'offre gratuite s'appliquent"), findsOneWidget);
  });

  testWidgets('an invitation refused by the plan offers to open "Mon offre"', (tester) async {
    final team =
        FakeTeamApi()
          ..inviteError = ApiException(
            "Votre offre permet 3 membres dans l'équipe (invitations en attente comprises).",
            statusCode: 403,
            code: 'ENTITLEMENT_LIMIT_REACHED',
          );
    await pumpAuthenticatedApp(tester, team: team, subscription: FakeSubscriptionApi(members: 3));
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Plus')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Équipe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inviter'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '+224620112233');
    await tester.tap(find.text("Envoyer l'invitation"));
    await tester.pumpAndSettle();

    expect(find.textContaining('Votre offre permet 3 membres'), findsOneWidget);
    expect(team.sent, isEmpty);
    await tester.tap(find.text('Voir mon offre'));
    await tester.pumpAndSettle();
    expect(find.text('Offre Gratuit'), findsOneWidget);
    expect(find.text('Limite atteinte'), findsOneWidget);
  });
}
