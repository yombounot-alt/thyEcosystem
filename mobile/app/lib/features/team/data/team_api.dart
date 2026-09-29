import 'package:dio/dio.dart';
import 'package:thy_core/thy_core.dart';

import 'team_models.dart';

/// The team of a business (members, invitations sent) and the invitations the signed-in user
/// received. Every rule (who may manage whom) is enforced by the server; the app only mirrors it.
class TeamApi {
  TeamApi(this._dio);

  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<List<TeamMember>> members(String businessId) => _call(() async {
    final response = await _dio.get('/businesses/$businessId/members');
    return [
      for (final m in response.data as List<dynamic>)
        TeamMember.fromJson(m as Map<String, dynamic>),
    ];
  });

  Future<List<SentInvitation>> sentInvitations(String businessId) => _call(() async {
    final response = await _dio.get('/businesses/$businessId/invitations');
    return [
      for (final i in response.data as List<dynamic>)
        SentInvitation.fromJson(i as Map<String, dynamic>),
    ];
  });

  Future<void> invite(String businessId, {required String phone, required String role}) => _call(
    () =>
        _dio.post('/businesses/$businessId/invitations', data: {'phone': phone, 'roleCode': role}),
  );

  Future<void> revokeInvitation(String businessId, String invitationId) =>
      _call(() => _dio.delete('/businesses/$businessId/invitations/$invitationId'));

  Future<void> changeRole(String businessId, String userId, String role) =>
      _call(() => _dio.patch('/businesses/$businessId/members/$userId', data: {'roleCode': role}));

  Future<void> setSuspended(String businessId, String userId, {required bool suspended}) => _call(
    () => _dio.put(
      '/businesses/$businessId/members/$userId/status',
      data: {'status': suspended ? 'SUSPENDED' : 'ACTIVE'},
    ),
  );

  Future<void> remove(String businessId, String userId) =>
      _call(() => _dio.delete('/businesses/$businessId/members/$userId'));

  // --- invitations received ------------------------------------------------------------------

  Future<List<ReceivedInvitation>> receivedInvitations() => _call(() async {
    final response = await _dio.get('/me/invitations');
    return [
      for (final i in response.data as List<dynamic>)
        ReceivedInvitation.fromJson(i as Map<String, dynamic>),
    ];
  });

  /// Returns the id of the business just joined.
  Future<String> accept(String invitationId) => _call(() async {
    final response = await _dio.post('/me/invitations/$invitationId/accept');
    return (response.data as Map<String, dynamic>)['businessId'] as String;
  });

  Future<void> decline(String invitationId) =>
      _call(() => _dio.post('/me/invitations/$invitationId/decline'));
}
