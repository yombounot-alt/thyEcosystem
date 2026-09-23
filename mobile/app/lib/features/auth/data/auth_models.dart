class TokenPair {
  const TokenPair({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;

  factory TokenPair.fromJson(Map<String, dynamic> json) {
    return TokenPair(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
    );
  }
}

class BusinessSummary {
  const BusinessSummary({
    required this.id,
    required this.name,
    required this.currency,
    required this.role,
    this.permissions = const [],
  });

  final String id;
  final String name;
  final String currency;

  /// Role code in this business (`OWNER`, `MANAGER`, `CASHIER`…).
  final String role;

  /// What the user may do here (role + individual overrides). The app only uses it to hide what
  /// would be refused anyway — the server checks every request.
  final List<String> permissions;

  bool can(String permission) => permissions.contains(permission);

  factory BusinessSummary.fromJson(Map<String, dynamic> json) {
    return BusinessSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      currency: json['currency'] as String,
      role: json['roleCode'] as String,
      permissions: [
        for (final p in (json['permissions'] as List<dynamic>? ?? const [])) p as String,
      ],
    );
  }
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.phone,
    required this.fullName,
    required this.email,
    required this.phoneVerified,
    required this.activeBusinessId,
    required this.businesses,
  });

  final String id;
  final String phone;

  /// Null until the person has given their name (asked once, right after the first sign-in).
  final String? fullName;
  final String? email;
  final bool phoneVerified;
  final String? activeBusinessId;
  final List<BusinessSummary> businesses;

  bool get hasName => fullName != null && fullName!.trim().isNotEmpty;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      phone: json['phone'] as String,
      fullName: json['fullName'] as String?,
      email: json['email'] as String?,
      phoneVerified: json['phoneVerified'] as bool,
      activeBusinessId: json['activeBusinessId'] as String?,
      businesses:
          (json['businesses'] as List<dynamic>)
              .map((b) => BusinessSummary.fromJson(b as Map<String, dynamic>))
              .toList(),
    );
  }
}
