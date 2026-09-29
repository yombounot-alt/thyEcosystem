/// Socle technique de l'app THY (docs/plans/phase-0-foundation.md L0.10) : aucune fonctionnalité
/// métier ici — les écrans et les modules vivent dans l'app (et, plus tard, leurs propres paquets).
library;

export 'src/api/api_client.dart';
export 'src/api/api_config.dart';
export 'src/api/api_exception.dart';
export 'src/api/json_helpers.dart';
export 'src/api/jwt_claims.dart';
export 'src/api/paginated.dart';
export 'src/api/request_id.dart';
export 'src/config/app_environment.dart';
export 'src/media/photo_picker.dart';
export 'src/modules/app_module.dart';
export 'src/money.dart';
export 'src/observability/crash_reporting.dart';
export 'src/offline/offline_cache.dart';
export 'src/offline/offline_providers.dart';
export 'src/offline/offline_read_interceptor.dart';
export 'src/providers.dart';
export 'src/scanning/barcode_scan_screen.dart';
export 'src/scanning/barcode_scanner.dart';
export 'src/scanning/scan_types.dart';
export 'src/sharing/file_sharer.dart';
export 'src/sharing/text_sharer.dart';
export 'src/storage/local_store.dart';
export 'src/storage/token_storage.dart';
export 'src/theme/formatters.dart';
export 'src/widgets/async_view.dart';
