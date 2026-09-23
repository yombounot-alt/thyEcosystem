/// The kinds of direct payment a customer can make to the owner.
class PaymentProvider {
  PaymentProvider._();

  static const orangeMoney = 'orange_money';
  static const mobileMoney = 'mobile_money';
  static const merchantCode = 'merchant_code';
  static const other = 'other';

  static const all = [orangeMoney, mobileMoney, merchantCode, other];

  static String label(String provider) {
    switch (provider) {
      case orangeMoney:
        return 'Orange Money';
      case mobileMoney:
        return 'Mobile Money';
      case merchantCode:
        return 'Code marchand';
      default:
        return 'Autre moyen de paiement';
    }
  }

  /// Payments to a merchant code are sent to a code, everything else to a phone number.
  static bool sendsToCode(String provider) => provider == merchantCode;
}

/// A way to pay the owner, as configured by the owner in "Paramètres → Moyens de paiement".
/// Nothing here is built into the app: the number, the code, the holder and the steps all come
/// from what the owner typed.
class PaymentOption {
  const PaymentOption({
    required this.id,
    required this.provider,
    required this.displayName,
    required this.instructionSteps,
    required this.hasLogo,
    required this.isActive,
    this.accountName,
    this.phoneNumber,
    this.merchantCode,
    this.instructions,
    this.ussdCode,
    this.updatedAt,
  });

  final String id;
  final String provider;
  final String displayName;
  final String? accountName;
  final String? phoneNumber;
  final String? merchantCode;

  /// The owner's own text (for editing); null when the default steps apply.
  final String? instructions;

  /// The steps the customer will read: the owner's, or the defaults of the provider.
  final List<String> instructionSteps;

  /// The code dialled by "Payer maintenant", with optional {numero} {montant} {code}.
  final String? ussdCode;
  final bool hasLogo;
  final bool isActive;
  final DateTime? updatedAt;

  /// What money must be sent to: the number, or for a merchant payment the code.
  String? get destination => PaymentProvider.sendsToCode(provider) ? merchantCode : phoneNumber;

  factory PaymentOption.fromJson(Map<String, dynamic> json) {
    return PaymentOption(
      id: json['id'] as String,
      provider: json['provider'] as String,
      displayName: json['displayName'] as String,
      accountName: json['accountName'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
      merchantCode: json['merchantCode'] as String?,
      instructions: json['instructions'] as String?,
      instructionSteps: [
        for (final step in (json['instructionSteps'] as List<dynamic>? ?? const [])) step as String,
      ],
      ussdCode: json['ussdCode'] as String?,
      hasLogo: json['hasLogo'] as bool? ?? false,
      isActive: json['isActive'] as bool? ?? true,
      updatedAt: json['updatedAt'] == null ? null : DateTime.parse(json['updatedAt'] as String),
    );
  }
}

/// What the owner types in the form. An optional field left empty is sent empty so the server
/// clears it.
class PaymentOptionInput {
  const PaymentOptionInput({
    required this.provider,
    this.displayName = '',
    this.accountName = '',
    this.phoneNumber = '',
    this.merchantCode = '',
    this.instructions = '',
    this.ussdCode = '',
    this.isActive = true,
  });

  final String provider;
  final String displayName;
  final String accountName;
  final String phoneNumber;
  final String merchantCode;
  final String instructions;
  final String ussdCode;
  final bool isActive;

  Map<String, dynamic> toJson() => {
    'provider': provider,
    'displayName': displayName.trim(),
    'accountName': accountName.trim(),
    'phoneNumber': phoneNumber.trim(),
    'merchantCode': merchantCode.trim(),
    'instructions': instructions.trim(),
    'ussdCode': ussdCode.trim(),
    'isActive': isActive,
  };
}
