import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thy_design_system/thy_design_system.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/api_error_snackbar.dart';
import '../../auth/application/auth_selectors.dart';
import '../application/team_providers.dart';
import '../data/team_models.dart';

/// "+224 620 00 00 00" → "+224620000000": people type numbers with spaces.
String normalizePhone(String input) => input.replaceAll(RegExp(r'[\s.\-()]'), '');

final _e164 = RegExp(r'^\+[1-9]\d{7,14}$');

/// Invites someone by phone number. Nothing secret is sent: the person signs in to THY with that
/// number and finds the invitation there (they also get an SMS telling them so).
class InviteMemberScreen extends ConsumerStatefulWidget {
  const InviteMemberScreen({super.key});

  @override
  ConsumerState<InviteMemberScreen> createState() => _InviteMemberScreenState();
}

class _InviteMemberScreenState extends ConsumerState<InviteMemberScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController(text: '+224');
  String _role = 'CASHIER';
  bool _loading = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final business = ref.read(activeBusinessProvider);
    if (business == null) return;
    setState(() => _loading = true);
    try {
      final phone = normalizePhone(_phone.text.trim());
      await ref.read(teamApiProvider).invite(business.id, phone: phone, role: _role);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Invitation envoyée à $phone. Cette personne se connecte à THY avec ce numéro pour '
            'rejoindre ${business.name}.',
          ),
        ),
      );
      context.pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      showApiError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = grantableRoles(ref.watch(myRoleProvider));
    return Scaffold(
      appBar: AppBar(title: const Text('Inviter un membre')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              AppTextField(
                controller: _phone,
                label: 'Numéro de téléphone',
                keyboardType: TextInputType.phone,
                validator:
                    (v) =>
                        _e164.hasMatch(normalizePhone(v?.trim() ?? ''))
                            ? null
                            : 'Numéro invalide (format international, ex. +224 6…)',
              ),
              const SizedBox(height: 24),
              Text('Rôle', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final role in roles)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: role == _role ? context.colors.primary : context.colors.border,
                      width: role == _role ? 1.5 : 1,
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(
                      role == _role ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: role == _role ? context.colors.primary : null,
                    ),
                    title: Text(roleLabel(role)),
                    subtitle: Text(roleDescription(role)),
                    onTap: () => setState(() => _role = role),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                "Les droits de chaque membre peuvent ensuite être ajustés un par un. L'invitation "
                'reste valable 7 jours.',
                style: TextStyle(color: context.colors.onSurfaceMuted),
              ),
              const SizedBox(height: 24),
              PrimaryButton(label: "Envoyer l'invitation", onPressed: _submit, loading: _loading),
            ],
          ),
        ),
      ),
    );
  }
}
