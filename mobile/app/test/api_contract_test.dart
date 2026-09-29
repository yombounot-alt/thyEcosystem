import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Contrat app ↔ backend (L0.10, « client API … depuis l'OpenAPI ») : chaque requête que l'app
/// envoie (méthode + chemin) doit exister dans le contrat OpenAPI versionné du backend
/// (docs/api/openapi.json, que la CI backend garde identique au code). Un renommage ou une
/// suppression de route côté serveur fait donc échouer la CI de l'app au lieu de casser en
/// production.
///
/// Choix assumé : pas de client généré (les clients écrits à la main sont typés, testés, et vérifiés
/// contre le vrai backend par test/live_api_test.dart) — ce test en donne la garantie principale
/// sans remplacer du code éprouvé.

/// `_dio.get('/products/$id')`, `dio.post(\n  '/businesses/$businessId/invitations', …)`…
final _call = RegExp(
  r'''\b_?dio\s*\.\s*(get|post|put|patch|delete)\s*(?:<[^>]*>)?\s*\(\s*(['"])(.*?)\2''',
  dotAll: true,
);

/// `/products/$id/image?x=1` → `/products/{}/image`, `/payments/${p.id}` → `/payments/{}`.
String normalizeAppPath(String raw) {
  final path = raw.split('?').first;
  return path.split('/').map((s) => s.startsWith(r'$') ? '{}' : s).join('/');
}

/// `/businesses/{businessId}/members/{userId}` → `/businesses/{}/members/{}`.
String normalizeSpecPath(String path) => path.replaceAll(RegExp(r'\{[^}]+\}'), '{}');

void main() {
  final spec =
      jsonDecode(File('../../docs/api/openapi.json').readAsStringSync()) as Map<String, dynamic>;
  final specOps = <String>{
    for (final e in (spec['paths'] as Map<String, dynamic>).entries)
      for (final method in (e.value as Map<String, dynamic>).keys)
        '${method.toUpperCase()} ${normalizeSpecPath(e.key)}',
  };

  final appOps = <String, List<String>>{};
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    for (final m in _call.allMatches(f.readAsStringSync())) {
      final op = '${m.group(1)!.toUpperCase()} ${normalizeAppPath(m.group(3)!)}';
      appOps.putIfAbsent(op, () => []).add(f.path.replaceAll(r'\', '/'));
    }
  }

  test('path normalisation', () {
    expect(normalizeAppPath(r'/products/$id/image'), '/products/{}/image');
    expect(normalizeAppPath(r'/payments/${payment.id}/proof?x=1'), '/payments/{}/proof');
    expect(
      normalizeSpecPath('/businesses/{businessId}/members/{userId}'),
      '/businesses/{}/members/{}',
    );
  });

  test('the scan finds the app\'s API calls (guards against a silently empty check)', () {
    expect(appOps.length, greaterThan(50));
    expect(appOps.keys, contains('POST /auth/otp/verify'));
    expect(appOps.keys, contains('POST /me/invitations/{}/accept'));
  });

  test('every request the app sends exists in the backend OpenAPI contract', () {
    final unknown = {
      for (final e in appOps.entries)
        if (!specOps.contains(e.key)) e.key: e.value.toSet().join(', '),
    };
    expect(unknown, isEmpty, reason: 'requêtes absentes de docs/api/openapi.json');
  });
}
