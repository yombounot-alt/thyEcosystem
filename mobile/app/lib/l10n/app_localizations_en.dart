// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'THY';

  @override
  String get splashUnreachable =>
      'Cannot reach the server.\nYou stay signed in: try again once the network is back.';

  @override
  String get commonRetry => 'Try again';

  @override
  String get commonSignOut => 'Sign out';

  @override
  String get commonContinue => 'Continue';

  @override
  String get onboardingManage => 'Run your shop simply';

  @override
  String get onboardingTrack => 'Follow your sales and your stock';

  @override
  String get onboardingProfit => 'Really understand your profit';

  @override
  String get onboardingOffline => 'Keep selling without a connection';

  @override
  String get onboardingStart => 'Get started';

  @override
  String get phoneTitle => 'Your number';

  @override
  String get phoneIntro =>
      'Enter your phone number: we send you a code by SMS. No password to remember.';

  @override
  String get phoneLabel => 'Phone';

  @override
  String get phoneInvalid => 'Invalid number (international format, e.g. +224 6…)';

  @override
  String get phoneAcceptTerms => 'I accept the terms of use and the privacy policy';

  @override
  String get phoneTermsRequired => 'Please accept the terms and the privacy policy.';

  @override
  String get phoneSendCode => 'Get the code';

  @override
  String get otpTitle => 'Verification';

  @override
  String otpSentTo(String phone) {
    return 'A code was sent to\n$phone';
  }

  @override
  String get otpNeedSixDigits => 'Enter the 6 digits of the code.';

  @override
  String get otpVerify => 'Verify';

  @override
  String get otpResend => 'Send the code again';

  @override
  String get otpResending => 'Sending...';

  @override
  String get otpResent => 'Code sent again.';

  @override
  String get otpChangeNumber => 'Change the number';

  @override
  String get nameTitle => 'Welcome';

  @override
  String get nameQuestion => 'What is your name?';

  @override
  String get nameLabel => 'Full name';

  @override
  String get nameRequired => 'Name required';
}
