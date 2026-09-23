import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../auth/application/auth_selectors.dart';
import '../application/sales_providers.dart';
import '../data/sale_models.dart';
import 'pending_sale.dart';
import 'pending_sales_repository.dart';

/// Either the server recorded the sale ([sale]) or it could not be reached and the sale is now
/// safely queued on the phone ([queued]).
class CheckoutOutcome {
  const CheckoutOutcome.sold(Sale this.sale) : queued = null;
  const CheckoutOutcome.queued(PendingSale this.queued) : sale = null;

  final Sale? sale;
  final PendingSale? queued;
}

/// The moment of truth at the till: the customer has paid, so the sale must never be lost just
/// because the network is down.
class CheckoutService {
  CheckoutService(this._ref);

  final Ref _ref;

  /// [provisional] is the receipt shown if the sale has to wait; its date is the time of the sale.
  ///
  /// Only "the server could not be reached" queues the sale. Any answer from the server (a refusal,
  /// an error) is passed on so the cashier sees it and can react, exactly as before.
  Future<CheckoutOutcome> checkout(CheckoutRequest request, {required Sale provisional}) async {
    try {
      return CheckoutOutcome.sold(await _ref.read(salesApiProvider).checkout(request));
    } on ApiException catch (e) {
      final businessId = _ref.read(activeBusinessProvider)?.id;
      if (!e.isConnectionProblem || businessId == null) rethrow;

      final pending = PendingSale(
        id: request.clientRequestId,
        businessId: businessId,
        createdAt: provisional.soldAt,
        request: request,
        receipt: provisional,
      );
      await _ref.read(pendingSalesProvider.notifier).add(pending);
      return CheckoutOutcome.queued(pending);
    }
  }
}

final checkoutServiceProvider = Provider<CheckoutService>((ref) => CheckoutService(ref));
