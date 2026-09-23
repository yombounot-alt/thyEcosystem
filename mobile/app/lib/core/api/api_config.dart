/// Base URL of the THY API, including the version prefix (see backend, default port 3300).
///
/// - Android emulator: 10.0.2.2 reaches the host machine's localhost.
/// - iOS simulator / desktop: use localhost directly.
/// - Physical device: use your machine's LAN IP (e.g. 192.168.x.x) instead.
const String apiBaseUrl = String.fromEnvironment(
  'THY_API_BASE_URL',
  defaultValue: 'http://10.0.2.2:3300/api/v1',
);
