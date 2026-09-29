import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thy_core/thy_core.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_selectors.dart';
import '../data/team_api.dart';
import '../data/team_models.dart';

final teamApiProvider = Provider<TeamApi>((ref) => TeamApi(ref.watch(dioProvider)));

/// Managing the team is the owner's and administrators' job (`members:manage`).
final canManageTeamProvider = Provider<bool>((ref) {
  return ref.watch(activeBusinessProvider)?.can('members:manage') ?? false;
});

/// Editing the business card (name, phone, address).
final canEditBusinessProvider = Provider<bool>((ref) {
  return ref.watch(activeBusinessProvider)?.can('business:settings') ?? false;
});

/// The signed-in user's role in the active business (drives which members they may manage).
final myRoleProvider = Provider<String?>((ref) => ref.watch(activeBusinessProvider)?.role);

final teamMembersProvider = FutureProvider.autoDispose<List<TeamMember>>((ref) {
  final business = ref.watch(activeBusinessProvider);
  if (business == null) return const [];
  return ref.watch(teamApiProvider).members(business.id);
});

final sentInvitationsProvider = FutureProvider.autoDispose<List<SentInvitation>>((ref) {
  final business = ref.watch(activeBusinessProvider);
  if (business == null) return const [];
  return ref.watch(teamApiProvider).sentInvitations(business.id);
});

/// Invitations waiting for the signed-in user (by phone number). Re-read when the profile changes.
final receivedInvitationsProvider = FutureProvider.autoDispose<List<ReceivedInvitation>>((ref) {
  final userId = ref.watch(authControllerProvider.select((s) => s.profile?.id));
  if (userId == null) return const [];
  return ref.watch(teamApiProvider).receivedInvitations();
});

/// Whether [myRole] may act on a member holding [targetRole] — mirrors the server's rules: never
/// the owner, and only the owner handles administrators.
bool canActOn({required String? myRole, required String targetRole}) {
  if (targetRole == 'OWNER') return false;
  if (myRole == 'OWNER') return true;
  return !ownerOnlyRoles.contains(targetRole);
}

/// Roles [myRole] may hand out.
List<String> grantableRoles(String? myRole) =>
    myRole == 'OWNER'
        ? assignableRoles
        : assignableRoles.where((r) => !ownerOnlyRoles.contains(r)).toList();
