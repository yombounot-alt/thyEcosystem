import '../config/app_environment.dart';

/// Base URL of the THY API, including the version prefix — see [resolveApiBaseUrl] for how it is
/// chosen per environment (dev: local backend; staging/prod: given at build time).
final String apiBaseUrl = resolveApiBaseUrl(AppEnvironment.current);
