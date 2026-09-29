import 'dart:convert';

/// The active business (`bizId` claim) carried by an access token, or null if there is none.
///
/// Only a hint for the app: the server re-checks membership on every request and never trusts
/// the claim. It is read from a token that may already be expired — the signature is irrelevant
/// here, we only want to hand the same business back when renewing the session.
String? activeBusinessIdFromToken(String? token) {
  if (token == null) return null;
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    final claims = jsonDecode(payload);
    final id = claims is Map ? claims['bizId'] : null;
    return id is String && id.isNotEmpty ? id : null;
  } catch (_) {
    return null;
  }
}
