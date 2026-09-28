/// Roles a member can be given (the owner is the creator of the business, never assigned).
const assignableRoles = ['ADMIN', 'MANAGER', 'CASHIER', 'STOCK_KEEPER', 'ACCOUNTANT', 'VIEWER'];

/// Only the owner manages administrators (the server enforces the same rule).
const ownerOnlyRoles = {'OWNER', 'ADMIN'};

String roleLabel(String code) => switch (code) {
  'OWNER' => 'Propriétaire',
  'ADMIN' => 'Administrateur',
  'MANAGER' => 'Gérant',
  'CASHIER' => 'Caissier',
  'STOCK_KEEPER' => 'Magasinier',
  'ACCOUNTANT' => 'Comptable',
  'VIEWER' => 'Lecteur',
  _ => code,
};

/// One line under each role in the invite form, so the owner knows what they are granting.
String roleDescription(String code) => switch (code) {
  'ADMIN' => "Tout, sauf l'abonnement : gère aussi l'équipe.",
  'MANAGER' => 'Ventes, stock, clients, dépenses, validation des paiements.',
  'CASHIER' => 'Encaisse les ventes et enregistre les crédits clients.',
  'STOCK_KEEPER' => 'Produits, entrées et sorties de stock.',
  'ACCOUNTANT' => 'Dépenses, crédits, rapports et bénéfices.',
  'VIEWER' => 'Consulte les ventes et les rapports, sans rien modifier.',
  _ => '',
};

class TeamMember {
  const TeamMember({
    required this.userId,
    required this.fullName,
    required this.phone,
    required this.role,
    required this.status,
  });

  final String userId;
  final String? fullName;
  final String phone;
  final String role;

  /// `ACTIVE` or `SUSPENDED` (removed members are not listed).
  final String status;

  bool get isOwner => role == 'OWNER';
  bool get isSuspended => status == 'SUSPENDED';
  String get displayName => (fullName?.trim().isNotEmpty ?? false) ? fullName!.trim() : phone;

  factory TeamMember.fromJson(Map<String, dynamic> json) => TeamMember(
    userId: json['userId'] as String,
    fullName: json['fullName'] as String?,
    phone: json['phone'] as String,
    role: json['roleCode'] as String,
    status: json['status'] as String,
  );
}

/// An invitation the business sent and that is still waiting for an answer.
class SentInvitation {
  const SentInvitation({
    required this.id,
    required this.phone,
    required this.role,
    required this.expiresAt,
  });

  final String id;
  final String phone;
  final String role;
  final DateTime expiresAt;

  factory SentInvitation.fromJson(Map<String, dynamic> json) => SentInvitation(
    id: json['id'] as String,
    phone: json['phone'] as String,
    role: json['roleCode'] as String,
    expiresAt: DateTime.parse(json['expiresAt'] as String),
  );
}

/// An invitation addressed to the signed-in user's phone number.
class ReceivedInvitation {
  const ReceivedInvitation({
    required this.id,
    required this.businessId,
    required this.businessName,
    required this.role,
    required this.invitedByName,
    required this.expiresAt,
  });

  final String id;
  final String businessId;
  final String businessName;
  final String role;
  final String? invitedByName;
  final DateTime expiresAt;

  factory ReceivedInvitation.fromJson(Map<String, dynamic> json) => ReceivedInvitation(
    id: json['id'] as String,
    businessId: json['businessId'] as String,
    businessName: json['businessName'] as String,
    role: json['roleCode'] as String,
    invitedByName: json['invitedByName'] as String?,
    expiresAt: DateTime.parse(json['expiresAt'] as String),
  );
}
