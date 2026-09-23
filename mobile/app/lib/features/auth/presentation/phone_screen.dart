import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/primary_button.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez accepter les conditions et la politique de confidentialité.'),
        ),
      );
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
    return Scaffold(
      appBar: AppBar(title: const Text('Votre numéro')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Entrez votre numéro de téléphone : nous vous envoyons un code par SMS. '
                  'Pas de mot de passe à retenir.',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                AppTextField(
                  controller: _phoneController,
                  label: 'Téléphone',
                  keyboardType: TextInputType.phone,
                  validator: (v) {
                    if (v == null || !RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(v.trim())) {
                      return 'Numéro invalide (format international, ex. +224 6…)';
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
                  title: const Text(
                    "J'accepte les conditions d'utilisation et la politique de confidentialité",
                    style: TextStyle(fontSize: 14),
                  ),
                ),
                const SizedBox(height: 16),
                PrimaryButton(label: 'Recevoir le code', onPressed: _submit, loading: _loading),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
