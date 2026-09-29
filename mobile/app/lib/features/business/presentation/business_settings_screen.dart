import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thy_design_system/thy_design_system.dart';
import 'package:thy_core/thy_core.dart';

import '../../auth/application/auth_controller.dart';
import '../../team/presentation/invite_member_screen.dart';
import '../application/business_providers.dart';
import '../data/business_api.dart';

final _e164 = RegExp(r'^\+[1-9]\d{7,14}$');

/// The business card: name, category, phone and address (printed on receipts).
/// The currency is shown but fixed: every amount already recorded is in that currency.
class BusinessSettingsScreen extends ConsumerWidget {
  const BusinessSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(businessDetailsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text("L'entreprise")),
      body: AsyncView<BusinessDetails>(
        value: details,
        onRetry: () => ref.invalidate(businessDetailsProvider),
        data: (d) => _BusinessForm(details: d),
      ),
    );
  }
}

class _BusinessForm extends ConsumerStatefulWidget {
  const _BusinessForm({required this.details});

  final BusinessDetails details;

  @override
  ConsumerState<_BusinessForm> createState() => _BusinessFormState();
}

class _BusinessFormState extends ConsumerState<_BusinessForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.details.name);
  late final _phone = TextEditingController(text: widget.details.phone ?? '');
  late final _address = TextEditingController(text: widget.details.address ?? '');
  late String _type =
      businessTypes.containsKey(widget.details.businessType)
          ? widget.details.businessType!
          : 'autre';
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(businessApiProvider)
          .update(
            widget.details.id,
            name: _name.text.trim(),
            businessType: _type,
            phone: normalizePhone(_phone.text.trim()),
            address: _address.text.trim(),
          );
      ref.invalidate(businessDetailsProvider);
      // The business name is also in the profile (tabs, business switcher).
      await ref.read(authControllerProvider.notifier).refreshProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Informations enregistrées')));
      context.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          AppTextField(
            controller: _name,
            label: "Nom de l'entreprise",
            validator: (v) => (v == null || v.trim().length < 2) ? 'Nom requis' : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Catégorie'),
            items: [
              for (final e in businessTypes.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 16),
          AppTextField(controller: _address, label: 'Adresse'),
          const SizedBox(height: 16),
          AppTextField(
            controller: _phone,
            label: "Téléphone de l'entreprise (facultatif)",
            keyboardType: TextInputType.phone,
            validator: (v) {
              final value = normalizePhone(v?.trim() ?? '');
              if (value.isEmpty) return null;
              return _e164.hasMatch(value) ? null : 'Format international requis (ex. +224 6…)';
            },
          ),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Devise'),
            child: Text(widget.details.currency),
          ),
          const SizedBox(height: 8),
          Text(
            'La devise ne change pas : tous les montants déjà enregistrés sont dans cette devise.',
            style: TextStyle(color: context.colors.onSurfaceMuted),
          ),
          const SizedBox(height: 24),
          PrimaryButton(label: 'Enregistrer', onPressed: _save, loading: _saving),
        ],
      ),
    );
  }
}
