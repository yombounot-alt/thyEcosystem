import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thy_app/features/auth/data/auth_models.dart';
import 'package:thy_app/features/notifications/data/notifications_api.dart';
import 'package:thy_app/features/team/data/team_models.dart';

import 'fakes.dart';

/// An account that can belong to several businesses, like the real server: `activateBusiness`
/// switches the active one, and accepting an invitation adds a business.
class MultiBusinessAuthApi extends FakeAuthApi {
  MultiBusinessAuthApi({required this.businesses, this.activeId}) : super();

  final List<BusinessSummary> businesses;
  String? activeId;
  final List<String> activated = [];

  @override
  Future<UserProfile> me() async => UserProfile(
    id: 'user-1',
    phone: '+224600000000',
    fullName: fullName,
    email: null,
    phoneVerified: true,
    activeBusinessId: activeId,
    businesses: List.of(businesses),
  );

  @override
  Future<String> activateBusiness(String businessId) async {
    activated.add(businessId);
    activeId = businessId;
    return 'access-$businessId';
  }
}

BusinessSummary business(String id, String name, {String role = 'OWNER', List<String>? perms}) =>
    BusinessSummary(
      id: id,
      name: name,
      currency: 'GNF',
      role: role,
      permissions: perms ?? FakeAuthApi().permissions,
    );

const cashierMember = TeamMember(
  userId: 'user-2',
  fullName: 'Awa Diallo',
  phone: '+224620000002',
  role: 'CASHIER',
  status: 'ACTIVE',
);

TeamMember ownerMember() => const TeamMember(
  userId: 'user-1',
  fullName: 'Tamba Camara',
  phone: '+224600000000',
  role: 'OWNER',
  status: 'ACTIVE',
);

Future<void> openMore(WidgetTester tester) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Plus')));
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).first);
  await tester.tap(find.text(text).first);
  await tester.pumpAndSettle();
}

void main() {
  group('team', () {
    testWidgets('the owner invites a cashier; the invitation waits in the team list', (
      tester,
    ) async {
      final team = FakeTeamApi();
      await pumpAuthenticatedApp(tester, team: team);
      await openMore(tester);
      await tapText(tester, 'Équipe');

      expect(find.text('Tamba Camara'), findsOneWidget);
      expect(find.textContaining('Vous travaillez seul'), findsOneWidget);

      await tapText(tester, 'Inviter');
      await tester.enterText(find.byType(TextFormField), '+224 620 11 22 33');
      await tapText(tester, 'Caissier');
      await tapText(tester, "Envoyer l'invitation");

      expect(team.sent.single.phone, '+224620112233'); // spaces removed
      expect(team.sent.single.role, 'CASHIER');
      expect(find.text('Invitations en attente (1)'), findsOneWidget);
      expect(find.text('+224620112233'), findsOneWidget);

      await tester.tap(find.byTooltip("Annuler l'invitation"));
      await tester.pumpAndSettle();
      expect(team.sent, isEmpty);
      expect(find.textContaining('Invitations en attente'), findsNothing);
    });

    testWidgets('an invalid number is refused before anything is sent', (tester) async {
      final team = FakeTeamApi();
      await pumpAuthenticatedApp(tester, team: team);
      await openMore(tester);
      await tapText(tester, 'Équipe');
      await tapText(tester, 'Inviter');
      await tester.enterText(find.byType(TextFormField), '0620112233');
      await tapText(tester, "Envoyer l'invitation");

      expect(find.textContaining('Numéro invalide'), findsOneWidget);
      expect(team.sent, isEmpty);
    });

    testWidgets('the owner changes a role, suspends, then removes a member (after confirming)', (
      tester,
    ) async {
      final team = FakeTeamApi(members: [ownerMember(), cashierMember]);
      await pumpAuthenticatedApp(tester, team: team);
      await openMore(tester);
      await tapText(tester, 'Équipe');

      // The owner row cannot be acted on; the cashier row can.
      await tapText(tester, 'Awa Diallo');
      await tapText(tester, 'Changer le rôle');
      await tapText(tester, 'Gérant');
      expect(team.members_.last.role, 'MANAGER');
      expect(find.textContaining('Gérant'), findsWidgets);

      await tapText(tester, 'Awa Diallo');
      await tapText(tester, "Suspendre l'accès");
      expect(team.members_.last.status, 'SUSPENDED');
      expect(find.textContaining('Suspendu'), findsOneWidget);

      await tapText(tester, 'Awa Diallo');
      await tapText(tester, "Retirer de l'équipe");
      expect(find.text('Retirer Awa Diallo ?'), findsOneWidget);
      await tapText(tester, 'Annuler');
      expect(team.members_, hasLength(2));

      await tapText(tester, 'Awa Diallo');
      await tapText(tester, "Retirer de l'équipe");
      await tester.tap(find.widgetWithText(FilledButton, 'Retirer'));
      await tester.pumpAndSettle();
      expect(team.members_, hasLength(1));
      expect(find.text('Awa Diallo'), findsNothing);
    });

    testWidgets('a cashier does not see team management nor the business settings', (tester) async {
      await pumpAuthenticatedApp(tester, authApi: FakeAuthApi(role: 'cashier'));
      await openMore(tester);
      expect(find.text('Équipe'), findsNothing);
      expect(find.text("Informations de l'entreprise"), findsNothing);
    });
  });

  group('invitations received', () {
    testWidgets('a new user who was invited joins the team instead of creating a business', (
      tester,
    ) async {
      final auth = MultiBusinessAuthApi(businesses: []);
      final team = FakeTeamApi(
        received: [
          ReceivedInvitation(
            id: 'inv-9',
            businessId: 'biz-9',
            businessName: 'Chez Fanta',
            role: 'CASHIER',
            invitedByName: 'Fanta Bah',
            expiresAt: DateTime.now().add(const Duration(days: 3)),
          ),
        ],
      );
      // Joining adds the business to the account, like the server does.
      final joining = _JoiningTeamApi(team, auth, business('biz-9', 'Chez Fanta', role: 'CASHIER'));
      await pumpAuthenticatedApp(tester, authApi: auth, team: joining);

      expect(find.text('On vous attend dans une équipe'), findsOneWidget);
      expect(find.text('Chez Fanta'), findsOneWidget);
      expect(find.textContaining('Invité par Fanta Bah'), findsOneWidget);

      await tapText(tester, 'Rejoindre');

      expect(team.accepted, ['inv-9']);
      expect(auth.activated, ['biz-9']);
      expect(find.byType(NavigationBar), findsOneWidget); // in the app, on Chez Fanta
      expect(find.text('Chez Fanta'), findsWidgets);
    });

    testWidgets('an invitation can be declined', (tester) async {
      final auth = MultiBusinessAuthApi(businesses: []);
      final team = FakeTeamApi(
        received: [
          ReceivedInvitation(
            id: 'inv-1',
            businessId: 'biz-9',
            businessName: 'Chez Fanta',
            role: 'VIEWER',
            invitedByName: null,
            expiresAt: DateTime.now().add(const Duration(days: 3)),
          ),
        ],
      );
      await pumpAuthenticatedApp(tester, authApi: auth, team: team);
      await tapText(tester, 'Refuser');
      expect(team.declined, ['inv-1']);
      expect(find.text('On vous attend dans une équipe'), findsNothing);
      expect(find.text('Votre entreprise'), findsOneWidget); // still free to create one
    });
  });

  group('several businesses', () {
    testWidgets('the user switches business from the "Plus" tab', (tester) async {
      final auth = MultiBusinessAuthApi(
        businesses: [business('biz-1', 'Boutique Demo'), business('biz-2', 'Dépôt Madina')],
        activeId: 'biz-1',
      );
      await pumpAuthenticatedApp(tester, authApi: auth);
      await openMore(tester);
      await tapText(tester, "Changer d'entreprise");
      await tapText(tester, 'Dépôt Madina');

      expect(auth.activated, ['biz-2']);
      expect(find.text('Dépôt Madina'), findsWidgets); // dashboard title
      expect(find.textContaining('Bonjour, Tamba'), findsOneWidget);
    });

    testWidgets('with a single business, no switcher is offered', (tester) async {
      await pumpAuthenticatedApp(tester);
      await openMore(tester);
      expect(find.text("Changer d'entreprise"), findsNothing);
      expect(find.text('Créer une autre entreprise'), findsOneWidget);
    });
  });

  group('notifications', () {
    AppNotification note(String id, String type, String title, {Map<String, String>? data}) =>
        AppNotification(
          id: id,
          type: type,
          title: title,
          body: 'Détail de $title',
          data: data ?? const {},
          readAt: null,
          createdAt: DateTime(2026, 9, 27, 10),
        );

    testWidgets('the bell shows the unread count; opening a stock alert marks it read and leads to '
        'the product', (tester) async {
      final notifications = FakeNotificationsApi([
        note(
          'n1',
          'STOCK_LOW',
          'Stock bas : Riz',
          data: {'businessId': 'biz-1', 'productId': 'p1'},
        ),
        note('n2', 'BUSINESS_WELCOME', 'Bienvenue sur THY'),
      ]);
      await pumpAuthenticatedApp(
        tester,
        notifications: notifications,
        products: FakeProductsApi([testProduct(id: 'p1', name: 'Riz 25 kg', stock: 2)]),
      );

      expect(find.byTooltip('Notifications (2 non lues)'), findsOneWidget);
      await tester.tap(find.byTooltip('Notifications (2 non lues)'));
      await tester.pumpAndSettle();

      expect(find.text('Stock bas : Riz'), findsOneWidget);
      await tapText(tester, 'Stock bas : Riz');
      expect(notifications.readIds, ['n1']);
      expect(find.text('Riz 25 kg'), findsWidgets); // product detail

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tapText(tester, 'Tout marquer lu');
      expect(notifications.items.every((n) => n.isRead), isTrue);
    });

    testWidgets('an empty inbox says so', (tester) async {
      await pumpAuthenticatedApp(tester);
      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();
      expect(find.text('Aucune notification pour le moment.'), findsOneWidget);
    });
  });

  group('profile and business card', () {
    testWidgets('the name can be changed from the profile', (tester) async {
      final auth = FakeAuthApi();
      await pumpAuthenticatedApp(tester, authApi: auth);
      await openMore(tester);
      await tapText(tester, 'Tamba Camara');
      await tester.enterText(find.byType(TextFormField), 'Tamba K. Camara');
      await tapText(tester, 'Enregistrer');
      expect(auth.fullName, 'Tamba K. Camara');
      expect(find.text('Profil enregistré'), findsOneWidget);
    });
  });
}

/// Accepting adds the business to the account (as the server would), then answers like the fake.
class _JoiningTeamApi extends FakeTeamApi {
  _JoiningTeamApi(this.inner, this.auth, this.joined) : super(received: inner.received_);

  final FakeTeamApi inner;
  final MultiBusinessAuthApi auth;
  final BusinessSummary joined;

  @override
  Future<String> accept(String invitationId) async {
    final id = await inner.accept(invitationId);
    auth.businesses.add(joined);
    return id;
  }
}
