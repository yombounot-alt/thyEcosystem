import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thy_design_system/thy_design_system.dart';
import 'package:thy_core/thy_core.dart';

import '../../auth/application/auth_controller.dart';
import '../application/team_providers.dart';
import '../data/team_models.dart';

/// Joins the business of [invitation] and makes it the active one.
Future<void> acceptInvitation(
  BuildContext context,
  WidgetRef ref,
  ReceivedInvitation invitation,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final businessId = await ref.read(teamApiProvider).accept(invitation.id);
    await ref.read(authControllerProvider.notifier).switchBusiness(businessId);
    messenger.showSnackBar(SnackBar(content: Text('Bienvenue dans ${invitation.businessName} !')));
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } finally {
    ref.invalidate(receivedInvitationsProvider);
  }
}

Future<void> declineInvitation(
  BuildContext context,
  WidgetRef ref,
  ReceivedInvitation invitation,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(teamApiProvider).decline(invitation.id);
    messenger.showSnackBar(const SnackBar(content: Text('Invitation refusée')));
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } finally {
    ref.invalidate(receivedInvitationsProvider);
  }
}

/// One invitation, with its two answers.
class ReceivedInvitationCard extends ConsumerStatefulWidget {
  const ReceivedInvitationCard({super.key, required this.invitation});

  final ReceivedInvitation invitation;

  @override
  ConsumerState<ReceivedInvitationCard> createState() => _ReceivedInvitationCardState();
}

class _ReceivedInvitationCardState extends ConsumerState<ReceivedInvitationCard> {
  bool _busy = false;

  Future<void> _answer(Future<void> Function() action) async {
    setState(() => _busy = true);
    await action();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.invitation;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(inv.businessName, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              [
                'Rôle proposé : ${roleLabel(inv.role)}',
                if (inv.invitedByName != null) 'Invité par ${inv.invitedByName}',
              ].join(' · '),
              style: TextStyle(color: context.colors.onSurfaceMuted),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _busy ? null : () => _answer(() => declineInvitation(context, ref, inv)),
                    child: const Text('Refuser'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed:
                        _busy ? null : () => _answer(() => acceptInvitation(context, ref, inv)),
                    child: const Text('Rejoindre'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The invitations waiting for the signed-in user (reachable from the "Plus" tab).
class ReceivedInvitationsScreen extends ConsumerWidget {
  const ReceivedInvitationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invitations = ref.watch(receivedInvitationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Invitations reçues')),
      body: AsyncView<List<ReceivedInvitation>>(
        value: invitations,
        onRetry: () => ref.invalidate(receivedInvitationsProvider),
        data:
            (list) =>
                list.isEmpty
                    ? const EmptyState(
                      icon: Icons.mark_email_read_outlined,
                      message: 'Aucune invitation en attente.',
                    )
                    : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final inv in list) ReceivedInvitationCard(invitation: inv),
                        TextButton(onPressed: () => context.pop(), child: const Text('Plus tard')),
                      ],
                    ),
      ),
    );
  }
}
