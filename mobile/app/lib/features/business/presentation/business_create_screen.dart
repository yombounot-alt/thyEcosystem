import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import 'package:go_router/go_router.dart';
import 'package:thy_design_system/thy_design_system.dart';

import '../../auth/application/auth_controller.dart';
import '../../team/application/team_providers.dart';
import '../../team/presentation/received_invitations.dart';
import '../application/business_providers.dart';
import '../data/business_api.dart';

class BusinessCreateScreen extends ConsumerStatefulWidget {
  /// [another]: opened from the app to add a business to an account that already has one (the
  /// screen closes once it is created). Otherwise it is the last step of the first sign-in.
  const BusinessCreateScreen({super.key, this.another = false});

  final bool another;

  @override
  ConsumerState<BusinessCreateScreen> createState() => _BusinessCreateScreenState();
}

class _BusinessCreateScreenState extends ConsumerState<BusinessCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  String _businessType = businessTypes.keys.first;
  String _currency = 'GNF';
  bool _loading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final result = await ref
          .read(businessApiProvider)
          .create(
            name: _nameController.text.trim(),
            businessType: _businessType,
            currency: _currency,
            phone: _phoneController.text.trim(),
            address: _addressController.text.trim(),
          );
      await ref.read(authControllerProvider.notifier).onBusinessCreated(result.accessToken);
      // First sign-in: the router's redirect moves on by itself once the auth state updates.
      if (widget.another && mounted) context.pop();
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
      appBar: AppBar(title: Text(widget.another ? 'Nouvelle entreprise' : 'Votre entreprise')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Someone invited this number: joining their team is usually why they are here.
                if (!widget.another) const _PendingInvitations(),
                Text(
                  widget.another
                      ? 'Chaque entreprise a ses propres produits, ventes et équipe.'
                      : 'Parlez-nous de votre commerce pour finaliser votre compte.',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                AppTextField(
                  controller: _nameController,
                  label: "Nom de l'entreprise",
                  validator: (v) => (v == null || v.trim().length < 2) ? 'Nom requis' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _businessType,
                  decoration: const InputDecoration(labelText: 'Catégorie'),
                  items:
                      businessTypes.entries
                          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                          .toList(),
                  onChanged: (v) => setState(() => _businessType = v ?? _businessType),
                ),
                const SizedBox(height: 16),
                AppTextField(controller: _addressController, label: 'Adresse'),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _phoneController,
                  label: "Téléphone de l'entreprise (facultatif)",
                  keyboardType: TextInputType.phone,
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isEmpty) return null;
                    return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value)
                        ? null
                        : 'Format international requis (ex. +224 6…)';
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _currency,
                  decoration: const InputDecoration(labelText: 'Devise'),
                  items: const [
                    DropdownMenuItem(value: 'GNF', child: Text('GNF — Franc guinéen')),
                    DropdownMenuItem(value: 'XOF', child: Text('XOF — Franc CFA')),
                    DropdownMenuItem(value: 'USD', child: Text('USD — Dollar américain')),
                  ],
                  onChanged: (v) => setState(() => _currency = v ?? _currency),
                ),
                const SizedBox(height: 24),
                PrimaryButton(label: 'Créer mon entreprise', onPressed: _submit, loading: _loading),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingInvitations extends ConsumerWidget {
  const _PendingInvitations();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invitations = ref.watch(receivedInvitationsProvider).value ?? const [];
    if (invitations.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('On vous attend dans une équipe', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final invitation in invitations) ReceivedInvitationCard(invitation: invitation),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              Expanded(child: Divider()),
              Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('ou')),
              Expanded(child: Divider()),
            ],
          ),
        ),
      ],
    );
  }
}
