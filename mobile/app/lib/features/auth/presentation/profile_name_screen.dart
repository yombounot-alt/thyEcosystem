import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thy_design_system/thy_design_system.dart';
import 'package:thy_core/thy_core.dart';

import '../../../l10n/app_localizations.dart';
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
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.nameTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t.nameQuestion, style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 24),
                AppTextField(
                  controller: _nameController,
                  label: t.nameLabel,
                  validator: (v) => (v == null || v.trim().length < 2) ? t.nameRequired : null,
                ),
                const SizedBox(height: 24),
                PrimaryButton(label: t.commonContinue, onPressed: _submit, loading: _loading),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
