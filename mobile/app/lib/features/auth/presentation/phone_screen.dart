import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thy_design_system/thy_design_system.dart';
import 'package:thy_core/thy_core.dart';

import '../../../l10n/app_localizations.dart';
import '../application/auth_controller.dart';

/// The one entry point: sign-up and sign-in are the same flow. A code sent by SMS proves the
/// number; the account is created the first time a number is verified.
class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController(text: '+224');
  bool _acceptedTerms = false;
  bool _loading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptedTerms) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).phoneTermsRequired)));
      return;
    }

    setState(() => _loading = true);
    try {
      final phone = _phoneController.text.trim();
      await ref.read(authControllerProvider.notifier).requestOtp(phone: phone);
      if (!mounted) return;
      context.go('/otp-verify?phone=${Uri.encodeComponent(phone)}');
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.phoneTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t.phoneIntro, style: TextStyle(fontSize: 16)),
                const SizedBox(height: 24),
                AppTextField(
                  controller: _phoneController,
                  label: t.phoneLabel,
                  keyboardType: TextInputType.phone,
                  validator: (v) {
                    if (v == null || !RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(v.trim())) {
                      return t.phoneInvalid;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _acceptedTerms,
                  onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
                  title: Text(t.phoneAcceptTerms, style: TextStyle(fontSize: 14)),
                ),
                const SizedBox(height: 16),
                PrimaryButton(label: t.phoneSendCode, onPressed: _submit, loading: _loading),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
