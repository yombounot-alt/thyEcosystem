import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/primary_button.dart';
import '../application/auth_controller.dart';

/// Asked once, right after the first sign-in: the sign-in itself needs only a phone number.
class ProfileNameScreen extends ConsumerStatefulWidget {
  const ProfileNameScreen({super.key});

  @override
  ConsumerState<ProfileNameScreen> createState() => _ProfileNameScreenState();
}

class _ProfileNameScreenState extends ConsumerState<ProfileNameScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      await ref.read(authControllerProvider.notifier).saveName(_nameController.text);
      // Navigation happens automatically via the router's redirect once auth state updates.
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
      appBar: AppBar(title: const Text('Bienvenue')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Comment vous appelez-vous ?', style: TextStyle(fontSize: 16)),
                const SizedBox(height: 24),
                AppTextField(
                  controller: _nameController,
                  label: 'Nom complet',
                  validator: (v) => (v == null || v.trim().length < 2) ? 'Nom requis' : null,
                ),
                const SizedBox(height: 24),
                PrimaryButton(label: 'Continuer', onPressed: _submit, loading: _loading),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
