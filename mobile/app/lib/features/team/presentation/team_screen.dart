import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/application/auth_selectors.dart';
import '../application/team_providers.dart';
import '../data/team_models.dart';

/// The business's team: members (role, suspended or not) and invitations still waiting for an
/// answer. Owner and administrators only (`members:manage`).
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(teamMembersProvider);
    ref.invalidate(sentInvitationsProvider);
    await ref.read(teamMembersProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(teamMembersProvider);
    final invitations = ref.watch(sentInvitationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Équipe')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final invited = await context.push<bool>('/team/invite');
          if (invited == true) ref.invalidate(sentInvitationsProvider);
        },
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Inviter'),
      ),
      body: AsyncView<List<TeamMember>>(
        value: members,
        onRetry: () => _refresh(ref),
        data:
            (list) => RefreshIndicator(
              onRefresh: () => _refresh(ref),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 96),
                children: [
                  _SectionTitle('Membres (${list.length})'),
                  for (final member in list) _MemberTile(member: member),
                  ...invitations.maybeWhen(
                    data:
                        (pending) => [
                          if (pending.isNotEmpty) ...[
                            const Divider(height: 32),
                            _SectionTitle('Invitations en attente (${pending.length})'),
                            for (final invitation in pending)
                              _InvitationTile(invitation: invitation),
                          ],
                        ],
                    orElse: () => const <Widget>[],
                  ),
                  if (list.length == 1)
                    Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Vous travaillez seul pour le moment. Invitez un caissier, un gérant ou '
                        'un magasinier : chacun n\'aura accès qu\'à ce que son rôle permet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.colors.onSurfaceMuted),
                      ),
                    ),
                ],
              ),
            ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({required this.member});

  final TeamMember member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myRole = ref.watch(myRoleProvider);
    final editable = canActOn(myRole: myRole, targetRole: member.role);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: member.isSuspended ? context.colors.border : context.colors.primary,
        child: Text(
          member.displayName.characters.first.toUpperCase(),
          style: TextStyle(
            color: member.isSuspended ? context.colors.onSurface : context.colors.onPrimary,
          ),
        ),
      ),
      title: Text(member.displayName),
      subtitle: Text(
        [
          roleLabel(member.role),
          if (member.fullName != null) member.phone,
          if (member.isSuspended) 'Suspendu',
        ].join(' · '),
      ),
      trailing: editable ? const Icon(Icons.more_vert) : null,
      onTap: editable ? () => _showActions(context, ref) : null,
    );
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder:
          (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(title: Text(member.displayName), subtitle: Text(roleLabel(member.role))),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Changer le rôle'),
                  onTap: () => Navigator.pop(sheetContext, 'role'),
                ),
                ListTile(
                  leading: Icon(member.isSuspended ? Icons.play_arrow : Icons.pause),
                  title: Text(member.isSuspended ? "Réactiver l'accès" : "Suspendre l'accès"),
                  onTap: () => Navigator.pop(sheetContext, 'suspend'),
                ),
                ListTile(
                  leading: Icon(Icons.person_remove_outlined, color: context.colors.danger),
                  title: Text(
                    "Retirer de l'équipe",
                    style: TextStyle(color: context.colors.danger),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'remove'),
                ),
              ],
            ),
          ),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'role':
        await _changeRole(context, ref);
      case 'suspend':
        await _run(
          context,
          ref,
          () => ref
              .read(teamApiProvider)
              .setSuspended(_businessId(ref), member.userId, suspended: !member.isSuspended),
          member.isSuspended ? 'Accès réactivé' : 'Accès suspendu',
        );
      case 'remove':
        final confirmed = await showDialog<bool>(
          context: context,
          builder:
              (dialogContext) => AlertDialog(
                title: Text('Retirer ${member.displayName} ?'),
                content: const Text(
                  "Son accès à l'entreprise cesse immédiatement. Ses ventes passées restent "
                  'enregistrées à son nom. Vous pourrez l\'inviter à nouveau plus tard.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Annuler'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: context.colors.danger),
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Retirer'),
                  ),
                ],
              ),
        );
        if (confirmed != true || !context.mounted) return;
        await _run(
          context,
          ref,
          () => ref.read(teamApiProvider).remove(_businessId(ref), member.userId),
          '${member.displayName} a été retiré',
        );
    }
  }

  Future<void> _changeRole(BuildContext context, WidgetRef ref) async {
    final roles = grantableRoles(ref.read(myRoleProvider));
    final chosen = await showDialog<String>(
      context: context,
      builder:
          (dialogContext) => SimpleDialog(
            title: const Text('Nouveau rôle'),
            children: [
              for (final role in roles)
                ListTile(
                  leading: Icon(
                    role == member.role ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: role == member.role ? context.colors.primary : null,
                  ),
                  title: Text(roleLabel(role)),
                  subtitle: Text(roleDescription(role)),
                  onTap: () => Navigator.pop(dialogContext, role),
                ),
            ],
          ),
    );
    if (chosen == null || chosen == member.role || !context.mounted) return;
    await _run(
      context,
      ref,
      () => ref.read(teamApiProvider).changeRole(_businessId(ref), member.userId, chosen),
      'Rôle mis à jour : ${roleLabel(chosen)}',
    );
  }
}

String _businessId(WidgetRef ref) => ref.read(activeBusinessProvider)!.id;

/// Runs a team action, shows the outcome, and reloads the list.
Future<void> _run(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() action,
  String success,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    messenger.showSnackBar(SnackBar(content: Text(success)));
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } finally {
    ref.invalidate(teamMembersProvider);
    ref.invalidate(sentInvitationsProvider);
  }
}

class _InvitationTile extends ConsumerWidget {
  const _InvitationTile({required this.invitation});

  final SentInvitation invitation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.mail_outline)),
      title: Text(invitation.phone),
      subtitle: Text(
        '${roleLabel(invitation.role)} · expire le ${formatDay(invitation.expiresAt.toLocal())}',
      ),
      trailing: IconButton(
        tooltip: "Annuler l'invitation",
        icon: const Icon(Icons.close),
        onPressed:
            () => _run(
              context,
              ref,
              () => ref.read(teamApiProvider).revokeInvitation(_businessId(ref), invitation.id),
              'Invitation annulée',
            ),
      ),
    );
  }
}
