import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thy_design_system/thy_design_system.dart';

import '../../../core/api/api_exception.dart';
import '../../auth/application/auth_controller.dart';

/// The signed-in person: their name (shown to their team and on receipts) and their number
/// (their identity — changing it is not possible here: it is how they sign in).
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: ref.read(authControllerProvider).profile?.fullName ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(authApiProvider).updateFullName(_name.text.trim());
      await ref.read(authControllerProvider.notifier).refreshProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profil enregistré')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authControllerProvider).profile;
    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              AppTextField(
                controller: _name,
                label: 'Nom complet',
                validator:
                    (v) =>
                        (v == null || v.trim().isEmpty)
                            ? 'Votre nom est requis'
                            : (v.trim().length > 120 ? '120 caractères maximum' : null),
              ),
              const SizedBox(height: 16),
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Téléphone'),
                child: Text(profile?.phone ?? ''),
              ),
              const SizedBox(height: 8),
              Text(
                'Votre numéro sert à vous connecter : il ne peut pas être modifié ici.',
                style: TextStyle(color: context.colors.onSurfaceMuted),
              ),
              const SizedBox(height: 24),
              PrimaryButton(label: 'Enregistrer', onPressed: _save, loading: _saving),
            ],
          ),
        ),
      ),
    );
  }
}
