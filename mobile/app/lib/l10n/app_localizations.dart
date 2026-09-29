import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('fr')];

  /// No description provided for @appName.
  ///
  /// In fr, this message translates to:
  /// **'THY'**
  String get appName;

  /// No description provided for @splashUnreachable.
  ///
  /// In fr, this message translates to:
  /// **'Impossible de joindre le serveur.\nVous restez connecté : réessayez dès que le réseau est de retour.'**
  String get splashUnreachable;

  /// No description provided for @commonRetry.
  ///
  /// In fr, this message translates to:
  /// **'Réessayer'**
  String get commonRetry;

  /// No description provided for @commonSignOut.
  ///
  /// In fr, this message translates to:
  /// **'Se déconnecter'**
  String get commonSignOut;

  /// No description provided for @commonContinue.
  ///
  /// In fr, this message translates to:
  /// **'Continuer'**
  String get commonContinue;

  /// No description provided for @onboardingManage.
  ///
  /// In fr, this message translates to:
  /// **'Gérez votre commerce simplement'**
  String get onboardingManage;

  /// No description provided for @onboardingTrack.
  ///
  /// In fr, this message translates to:
  /// **'Suivez vos ventes et votre stock'**
  String get onboardingTrack;

  /// No description provided for @onboardingProfit.
  ///
  /// In fr, this message translates to:
  /// **'Comprenez réellement vos bénéfices'**
  String get onboardingProfit;

  /// No description provided for @onboardingOffline.
  ///
  /// In fr, this message translates to:
  /// **'Vendez même sans connexion'**
  String get onboardingOffline;

  /// No description provided for @onboardingStart.
  ///
  /// In fr, this message translates to:
  /// **'Commencer'**
  String get onboardingStart;

  /// No description provided for @phoneTitle.
  ///
  /// In fr, this message translates to:
  /// **'Votre numéro'**
  String get phoneTitle;

  /// No description provided for @phoneIntro.
  ///
  /// In fr, this message translates to:
  /// **'Entrez votre numéro de téléphone : nous vous envoyons un code par SMS. Pas de mot de passe à retenir.'**
  String get phoneIntro;

  /// No description provided for @phoneLabel.
  ///
  /// In fr, this message translates to:
  /// **'Téléphone'**
  String get phoneLabel;

  /// No description provided for @phoneInvalid.
  ///
  /// In fr, this message translates to:
  /// **'Numéro invalide (format international, ex. +224 6…)'**
  String get phoneInvalid;

  /// No description provided for @phoneAcceptTerms.
  ///
  /// In fr, this message translates to:
  /// **'J\'accepte les conditions d\'utilisation et la politique de confidentialité'**
  String get phoneAcceptTerms;

  /// No description provided for @phoneTermsRequired.
  ///
  /// In fr, this message translates to:
  /// **'Veuillez accepter les conditions et la politique de confidentialité.'**
  String get phoneTermsRequired;

  /// No description provided for @phoneSendCode.
  ///
  /// In fr, this message translates to:
  /// **'Recevoir le code'**
  String get phoneSendCode;

  /// No description provided for @otpTitle.
  ///
  /// In fr, this message translates to:
  /// **'Vérification'**
  String get otpTitle;

  /// No description provided for @otpSentTo.
  ///
  /// In fr, this message translates to:
  /// **'Un code a été envoyé au\n{phone}'**
  String otpSentTo(String phone);

  /// No description provided for @otpNeedSixDigits.
  ///
  /// In fr, this message translates to:
  /// **'Entrez les 6 chiffres du code.'**
  String get otpNeedSixDigits;

  /// No description provided for @otpVerify.
  ///
  /// In fr, this message translates to:
  /// **'Vérifier'**
  String get otpVerify;

  /// No description provided for @otpResend.
  ///
  /// In fr, this message translates to:
  /// **'Renvoyer le code'**
  String get otpResend;

  /// No description provided for @otpResending.
  ///
  /// In fr, this message translates to:
  /// **'Envoi...'**
  String get otpResending;

  /// No description provided for @otpResent.
  ///
  /// In fr, this message translates to:
  /// **'Code renvoyé.'**
  String get otpResent;

  /// No description provided for @otpChangeNumber.
  ///
  /// In fr, this message translates to:
  /// **'Modifier le numéro'**
  String get otpChangeNumber;

  /// No description provided for @nameTitle.
  ///
  /// In fr, this message translates to:
  /// **'Bienvenue'**
  String get nameTitle;

  /// No description provided for @nameQuestion.
  ///
  /// In fr, this message translates to:
  /// **'Comment vous appelez-vous ?'**
  String get nameQuestion;

  /// No description provided for @nameLabel.
  ///
  /// In fr, this message translates to:
  /// **'Nom complet'**
  String get nameLabel;

  /// No description provided for @nameRequired.
  ///
  /// In fr, this message translates to:
  /// **'Nom requis'**
  String get nameRequired;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
