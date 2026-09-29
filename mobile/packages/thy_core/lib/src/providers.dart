import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'offline/offline_providers.dart';
import 'storage/token_storage.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    ref.watch(tokenStorageProvider),
    cache: ref.watch(offlineCacheProvider),
    scope: () => ref.read(offlineScopeProvider),
    onReachability: (reachable) => ref.read(connectionStatusProvider.notifier).report(reachable),
  );
});

final dioProvider = Provider<Dio>((ref) => ref.watch(apiClientProvider).dio);
