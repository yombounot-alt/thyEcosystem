import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thy_design_system/thy_design_system.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/application/auth_selectors.dart';
import '../../team/application/team_providers.dart';
import '../application/notifications_providers.dart';
import '../data/notifications_api.dart';

IconData _iconFor(String type) => switch (type) {
  'STOCK_LOW' || 'STOCK_NEGATIVE' => Icons.inventory_2_outlined,
  'BUSINESS_INVITATION' => Icons.mail_outline,
  'TEAM_MEMBER_JOINED' || 'MEMBER_JOINED' => Icons.group_add_outlined,
  'MEMBER_ROLE_CHANGED' || 'MEMBER_PERMISSIONS_CHANGED' => Icons.badge_outlined,
  'MEMBER_REMOVED' => Icons.person_remove_outlined,
  'SECURITY_SESSION_REVOKED' => Icons.shield_outlined,
  _ => Icons.notifications_none,
};

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  /// Where a notification leads, if anywhere the user can go from the active business.
  String? _destination(WidgetRef ref, AppNotification n) {
    final activeId = ref.read(activeBusinessProvider)?.id;
    final sameBusiness = n.data['businessId'] == null || n.data['businessId'] == activeId;
    switch (n.type) {
      case 'STOCK_LOW':
      case 'STOCK_NEGATIVE':
        final productId = n.data['productId'];
        return sameBusiness && productId != null && productId.isNotEmpty
            ? '/products/$productId'
            : null;
      case 'BUSINESS_INVITATION':
        return '/invitations';
      case 'TEAM_MEMBER_JOINED':
        return sameBusiness && ref.read(canManageTeamProvider) ? '/team' : null;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationsProvider);
    final hasUnread = state.value?.items.any((n) => !n.isRead) ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: () async {
                try {
                  await ref.read(notificationsProvider.notifier).markAllRead();
                } on ApiException catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                }
              },
              child: const Text('Tout marquer lu'),
            ),
        ],
      ),
      body: AsyncView<NotificationsState>(
        value: state,
        onRetry: () => ref.invalidate(notificationsProvider),
        data:
            (inbox) =>
                inbox.items.isEmpty
                    ? const EmptyState(
                      icon: Icons.notifications_none,
                      message: 'Aucune notification pour le moment.',
                    )
                    : RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(notificationsProvider);
                        ref.invalidate(unreadNotificationsProvider);
                        await ref.read(notificationsProvider.future);
                      },
                      child: ListView.separated(
                        itemCount: inbox.items.length + (inbox.hasMore ? 1 : 0),
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          if (index == inbox.items.length) {
                            return Padding(
                              padding: const EdgeInsets.all(16),
                              child:
                                  inbox.loadingMore
                                      ? const Center(child: CircularProgressIndicator())
                                      : OutlinedButton(
                                        onPressed:
                                            () =>
                                                ref.read(notificationsProvider.notifier).loadMore(),
                                        child: const Text('Voir plus'),
                                      ),
                            );
                          }
                          final n = inbox.items[index];
                          final destination = _destination(ref, n);
                          return ListTile(
                            tileColor:
                                n.isRead ? null : context.colors.primary.withValues(alpha: 0.05),
                            leading: Icon(
                              _iconFor(n.type),
                              color:
                                  n.isRead ? context.colors.onSurfaceMuted : context.colors.primary,
                            ),
                            title: Text(
                              n.title,
                              style: TextStyle(
                                fontWeight: n.isRead ? FontWeight.w400 : FontWeight.w600,
                              ),
                            ),
                            subtitle: Text('${n.body}\n${formatDateTime(n.createdAt)}'),
                            isThreeLine: true,
                            trailing: destination != null ? const Icon(Icons.chevron_right) : null,
                            onTap: () {
                              ref.read(notificationsProvider.notifier).markRead(n);
                              if (destination != null) context.push(destination);
                            },
                          );
                        },
                      ),
                    ),
      ),
    );
  }
}
