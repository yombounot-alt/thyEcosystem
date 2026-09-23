import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thy_app/core/api/jwt_claims.dart';

String _token(Map<String, Object?> claims) {
  String b64(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${b64({'alg': 'HS256'})}.${b64(claims)}.signature';
}

void main() {
  group('activeBusinessIdFromToken', () {
    test('reads the bizId claim, even when the token has expired', () {
      final token = _token({'sub': 'user-1', 'bizId': 'biz-1', 'exp': 1});
      expect(activeBusinessIdFromToken(token), 'biz-1');
    });

    test('no business selected → null', () {
      expect(activeBusinessIdFromToken(_token({'sub': 'user-1'})), isNull);
      expect(activeBusinessIdFromToken(_token({'sub': 'user-1', 'bizId': ''})), isNull);
      expect(activeBusinessIdFromToken(_token({'sub': 'user-1', 'bizId': 42})), isNull);
    });

    test('anything that is not a JWT → null, never a crash', () {
      expect(activeBusinessIdFromToken(null), isNull);
      expect(activeBusinessIdFromToken(''), isNull);
      expect(activeBusinessIdFromToken('old-access'), isNull);
      expect(activeBusinessIdFromToken('a.b.c'), isNull);
      expect(activeBusinessIdFromToken('a.!!!.c'), isNull);
    });
  });
}
