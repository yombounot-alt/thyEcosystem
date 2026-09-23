import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/primary_button.dart';
import '../application/customers_providers.dart';
import '../data/customer_models.dart';

/// Creates a customer, or edits [customerId] when given.
class CustomerFormScreen extends ConsumerWidget {
  const CustomerFormScreen({super.key, this.customerId});

  final String? customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = customerId;
    if (id == null) return const _CustomerForm();

    return ref
        .watch(customerProvider(id))
        .when(
          data: (customer) => _CustomerForm(customer: customer),
          loading:
              () => Scaffold(
                appBar: AppBar(title: const Text('Modifier le client')),
                body: const Center(child: CircularProgressIndicator()),
              ),
          error:
              (error, _) => Scaffold(
                appBar: AppBar(title: const Text('Modifier le client')),
                body: ErrorRetry(
                  message: errorMessage(error),
                  onRetry: () => ref.invalidate(customerProvider(id)),
                ),
              ),
        );
  }
}

class _CustomerForm extends ConsumerStatefulWidget {
  const _CustomerForm({this.customer});

  final Customer? customer;

  @override
  ConsumerState<_CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends ConsumerState<_CustomerForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _notes;
  bool _saving = false;

  bool get _isEditing => widget.customer != null;

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    _name = TextEditingController(text: c?.fullName);
    _phone = TextEditingController(text: c?.phone);
    _address = TextEditingController(text: c?.address);
    _notes = TextEditingController(text: c?.notes);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? _blankToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final input = CustomerInput(
      fullName: _name.text.trim(),
      phone: _blankToNull(_phone.text),
      address: _blankToNull(_address.text),
      notes: _blankToNull(_notes.text),
    );

    setState(() => _saving = true);
    try {
      final api = ref.read(customersApiProvider);
      final existing = widget.customer;
      if (existing == null) {
        await api.create(
          fullName: input.fullName,
          phone: input.phone,
          address: input.address,
          notes: input.notes,
        );
      } else {
        await api.update(existing.id, input);
      }
      invalidateCustomerData(ref, customerId: existing?.id);
      if (!mounted) return;
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
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Modifier le client' : 'Nouveau client')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextField(
                  controller: _name,
                  label: 'Nom complet',
                  validator:
                      (v) =>
                          (v == null || v.trim().length < 2)
                              ? 'Nom requis (2 caractères minimum)'
                              : null,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _phone,
                  label: 'Téléphone (facultatif)',
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                AppTextField(controller: _address, label: 'Adresse (facultatif)'),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notes,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notes (facultatif)'),
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: _isEditing ? 'Enregistrer' : 'Ajouter le client',
                  onPressed: _submit,
                  loading: _saving,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
