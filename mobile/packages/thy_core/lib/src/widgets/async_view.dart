import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thy_design_system/thy_design_system.dart';

import '../api/api_exception.dart';

String errorMessage(Object error) {
  if (error is ApiException) return error.message;
  return 'Une erreur est survenue. Veuillez réessayer.';
}

/// Renders the loading / error(+retry) / data states of an [AsyncValue] consistently.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.data, this.onRetry});

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: data,
      loading: () => const LoadingState(),
      error: (error, _) => ErrorRetry(message: errorMessage(error), onRetry: onRetry),
    );
  }
}
