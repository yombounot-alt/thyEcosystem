import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thy_core/thy_core.dart';

import '../../auth/application/auth_controller.dart';
import '../data/notifications_api.dart';

final notificationsApiProvider = Provider<NotificationsApi>(
  (ref) => NotificationsApi(ref.watch(dioProvider)),
);

/// How often the unread badge looks again. Null switches the timer off (tests).
final notificationsRefreshProvider = Provider<Duration?>((ref) => const Duration(seconds: 60));

/// Unread notifications of the signed-in user (0 when offline: a badge, never an error).
final unreadNotificationsProvider = FutureProvider.autoDispose<int>((ref) async {
  final userId = ref.watch(authControllerProvider.select((s) => s.profile?.id));
  if (userId == null) return 0;
  final every = ref.watch(notificationsRefreshProvider);
  if (every != null) {
    final timer = Timer(every, ref.invalidateSelf);
    ref.onDispose(timer.cancel);
  }
  try {
    return await ref.watch(notificationsApiProvider).unreadCount();
  } on ApiException {
    return 0;
  }
});

class NotificationsState {
  const NotificationsState({
    required this.items,
    required this.nextCursor,
    this.loadingMore = false,
  });

  final List<AppNotification> items;
  final String? nextCursor;
  final bool loadingMore;

  bool get hasMore => nextCursor != null;

  NotificationsState copyWith({
    List<AppNotification>? items,
    String? nextCursor,
    bool? loadingMore,
  }) => NotificationsState(
    items: items ?? this.items,
    nextCursor: nextCursor ?? this.nextCursor,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// The inbox, page by page (newest first).
final notificationsProvider =
    AsyncNotifierProvider.autoDispose<NotificationsController, NotificationsState>(
      NotificationsController.new,
    );

class NotificationsController extends AsyncNotifier<NotificationsState> {
  @override
  Future<NotificationsState> build() async {
    final page = await ref.watch(notificationsApiProvider).list();
    return NotificationsState(items: page.items, nextCursor: page.nextCursor);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref.read(notificationsApiProvider).list(cursor: current.nextCursor);
      state = AsyncData(
        NotificationsState(items: [...current.items, ...page.items], nextCursor: page.nextCursor),
      );
    } on ApiException {
      state = AsyncData(current.copyWith(loadingMore: false));
      rethrow;
    }
  }

  Future<void> markRead(AppNotification notification) async {
    if (notification.isRead) return;
    final current = state.value;
    if (current != null) {
      state = AsyncData(
        current.copyWith(
          items: [for (final n in current.items) n.id == notification.id ? n.markedRead() : n],
        ),
      );
    }
    try {
      await ref.read(notificationsApiProvider).markRead(notification.id);
    } on ApiException {
      // Offline: it will show as unread again next time — nothing is lost.
    }
    ref.invalidate(unreadNotificationsProvider);
  }

  Future<void> markAllRead() async {
    await ref.read(notificationsApiProvider).markAllRead();
    final current = state.value;
    if (current != null) {
      state = AsyncData(current.copyWith(items: [for (final n in current.items) n.markedRead()]));
    }
    ref.invalidate(unreadNotificationsProvider);
  }
}
