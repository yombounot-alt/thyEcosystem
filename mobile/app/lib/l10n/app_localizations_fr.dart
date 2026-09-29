// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appName => 'THY';

  @override
  String get splashUnreachable =>
      'Impossible de joindre le serveur.\nVous restez connecté : réessayez dès que le réseau est de retour.';

  @override
  String get commonRetry => 'Réessayer';

  @override
  String get commonSignOut => 'Se déconnecter';

  @override
  String get commonContinue => 'Continuer';

  @override
  String get onboardingManage => 'Gérez votre commerce simplement';

  @override
  String get onboardingTrack => 'Suivez vos ventes et votre stock';

  @override
  String get onboardingProfit => 'Comprenez réellement vos bénéfices';

  @override
  String get onboardingOffline => 'Vendez même sans connexion';

  @override
  String get onboardingStart => 'Commencer';

  @override
  String get phoneTitle => 'Votre numéro';

  @override
  String get phoneIntro =>
      'Entrez votre numéro de téléphone : nous vous envoyons un code par SMS. Pas de mot de passe à retenir.';

  @override
  String get phoneLabel => 'Téléphone';

  @override
  String get phoneInvalid => 'Numéro invalide (format international, ex. +224 6…)';

  @override
  String get phoneAcceptTerms =>
      'J\'accepte les conditions d\'utilisation et la politique de confidentialité';

  @override
  String get phoneTermsRequired =>
      'Veuillez accepter les conditions et la politique de confidentialité.';

  @override
  String get phoneSendCode => 'Recevoir le code';

  @override
  String get otpTitle => 'Vérification';

  @override
  String otpSentTo(String phone) {
    return 'Un code a été envoyé au\n$phone';
  }

  @override
  String get otpNeedSixDigits => 'Entrez les 6 chiffres du code.';

  @override
  String get otpVerify => 'Vérifier';

  @override
  String get otpResend => 'Renvoyer le code';

  @override
  String get otpResending => 'Envoi...';

  @override
  String get otpResent => 'Code renvoyé.';

  @override
  String get otpChangeNumber => 'Modifier le numéro';

  @override
  String get nameTitle => 'Bienvenue';

  @override
  String get nameQuestion => 'Comment vous appelez-vous ?';

  @override
  String get nameLabel => 'Nom complet';

  @override
  String get nameRequired => 'Nom requis';
}
