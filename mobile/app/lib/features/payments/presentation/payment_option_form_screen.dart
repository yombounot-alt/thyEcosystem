import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/media/photo_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/primary_button.dart';
import '../application/payments_providers.dart';
import '../data/payment_method_models.dart';
import 'payment_visuals.dart';

/// Adds a payment option, or edits [optionId]. Everything a customer will see — the holder, the
/// number, the code, the steps, the logo — is typed here by the owner.
class PaymentOptionFormScreen extends ConsumerWidget {
  const PaymentOptionFormScreen({super.key, this.optionId});

  final String? optionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = optionId;
    if (id == null) return const _PaymentOptionForm();

    return ref
        .watch(paymentOptionsProvider)
        .when(
          data: (options) {
            final found = options.where((o) => o.id == id).firstOrNull;
            if (found == null) {
              return Scaffold(
                appBar: AppBar(title: const Text('Moyen de paiement')),
                body: const EmptyState(
                  icon: Icons.search_off,
                  message: 'Ce moyen de paiement est introuvable.',
                ),
              );
            }
            return _PaymentOptionForm(option: found);
          },
          loading:
              () => Scaffold(
                appBar: AppBar(title: const Text('Moyen de paiement')),
                body: const Center(child: CircularProgressIndicator()),
              ),
          error:
              (error, _) => Scaffold(
                appBar: AppBar(title: const Text('Moyen de paiement')),
                body: ErrorRetry(
                  message: errorMessage(error),
                  onRetry: () => ref.invalidate(paymentOptionsProvider),
                ),
              ),
        );
  }
}

class _PaymentOptionForm extends ConsumerStatefulWidget {
  const _PaymentOptionForm({this.option});

  final PaymentOption? option;

  @override
  ConsumerState<_PaymentOptionForm> createState() => _PaymentOptionFormState();
}

class _PaymentOptionFormState extends ConsumerState<_PaymentOptionForm> {
  static final _phonePattern = RegExp(r'^\+?\d{6,15}$');

  final _formKey = GlobalKey<FormState>();
  late String _provider;
  late final TextEditingController _name;
  late final TextEditingController _holder;
  late final TextEditingController _phone;
  late final TextEditingController _code;
  late final TextEditingController _ussd;
  late final TextEditingController _instructions;
  late bool _active;

  /// A logo picked but not sent yet, and whether the current one is to be removed.
  PickedPhoto? _newLogo;
  bool _removeLogo = false;
  bool _saving = false;

  bool get _editing => widget.option != null;

  @override
  void initState() {
    super.initState();
    final o = widget.option;
    _provider = o?.provider ?? PaymentProvider.orangeMoney;
    _name = TextEditingController(text: o?.displayName ?? '');
    _holder = TextEditingController(text: o?.accountName ?? '');
    _phone = TextEditingController(text: o?.phoneNumber ?? '');
    _code = TextEditingController(text: o?.merchantCode ?? '');
    _ussd = TextEditingController(text: o?.ussdCode ?? '');
    _instructions = TextEditingController(text: o?.instructions ?? '');
    _active = o?.isActive ?? true;
  }

  @override
  void dispose() {
    for (final c in [_name, _holder, _phone, _code, _ussd, _instructions]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _needsPhone =>
      _provider == PaymentProvider.orangeMoney || _provider == PaymentProvider.mobileMoney;
  bool get _showsPhone => _provider != PaymentProvider.merchantCode;
  bool get _showsCode =>
      _provider == PaymentProvider.merchantCode || _provider == PaymentProvider.other;

  String? _validatePhone(String? value) {
    final text = (value ?? '').trim();
    final compact = text.replaceAll(RegExp(r'[\s().-]'), '');
    if (text.isEmpty) {
      if (_needsPhone) return 'Saisissez le numéro.';
      if (_provider == PaymentProvider.other && _code.text.trim().isEmpty) {
        return 'Indiquez un numéro ou un code marchand.';
      }
      return null;
    }
    return _phonePattern.hasMatch(compact) ? null : 'Numéro invalide (6 à 15 chiffres).';
  }

  String? _validateCode(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      if (_provider == PaymentProvider.merchantCode) return 'Saisissez le code marchand.';
      return null;
    }
    return RegExp(r'^[A-Za-z0-9][A-Za-z0-9 _-]{1,39}$').hasMatch(text)
        ? null
        : 'Code invalide (lettres, chiffres, espace, tiret).';
  }

  String? _validateUssd(String? value) {
    final text = (value ?? '').replaceAll(RegExp(r'\s'), '');
    if (text.isEmpty) return null;
    final rest = text.replaceAll(RegExp(r'\{(numero|montant|code)\}'), '');
    return RegExp(r'^[0-9*#+]*$').hasMatch(rest) && text.length <= 60
        ? null
        : 'Seuls les chiffres, * # + et {numero} {montant} {code} sont acceptés.';
  }

  Future<void> _pickLogo() async {
    final photo = await ref.read(photoPickerProvider)(PhotoSource.gallery);
    if (photo == null || !mounted) return;
    if (photo.bytes.length > 1024 * 1024) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Logo trop lourd (1 Mo maximum).')));
      return;
    }
    setState(() {
      _newLogo = photo;
      _removeLogo = false;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final input = PaymentOptionInput(
      provider: _provider,
      displayName: _name.text,
      accountName: _holder.text,
      phoneNumber: _showsPhone ? _phone.text : '',
      merchantCode: _showsCode ? _code.text : '',
      instructions: _instructions.text,
      ussdCode: _ussd.text,
      isActive: _active,
    );

    try {
      final api = ref.read(paymentMethodsApiProvider);
      final saved = _editing ? await api.update(widget.option!.id, input) : await api.create(input);

      // The logo travels separately; a failure there must not lose what was just saved.
      String? logoProblem;
      try {
        final logo = _newLogo;
        if (logo != null) {
          await api.uploadLogo(saved.id, logo.bytes, logo.filename);
        } else if (_removeLogo && saved.hasLogo) {
          await api.deleteLogo(saved.id);
        }
      } on ApiException catch (e) {
        logoProblem = e.message;
      }

      ref.invalidate(paymentOptionsProvider);
      if (!mounted) return;
      if (logoProblem != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enregistré, mais le logo n’a pas été envoyé : $logoProblem')),
        );
      }
      context.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final option = widget.option!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Supprimer ce moyen de paiement ?'),
            content: Text('« ${option.displayName} » ne sera plus proposé à vos clients.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Annuler'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                child: const Text('Supprimer'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(paymentMethodsApiProvider).delete(option.id);
      ref.invalidate(paymentOptionsProvider);
      if (mounted) context.pop();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final option = widget.option;
    final hasCurrentLogo = option != null && option.hasLogo && !_removeLogo && _newLogo == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Modifier le moyen de paiement' : 'Nouveau moyen de paiement'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<String>(
                initialValue: _provider,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  for (final provider in PaymentProvider.all)
                    DropdownMenuItem(value: provider, child: Text(PaymentProvider.label(provider))),
                ],
                onChanged: (value) => setState(() => _provider = value ?? _provider),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                maxLength: 60,
                decoration: InputDecoration(
                  labelText: 'Nom affiché',
                  helperText: 'Vide : « ${PaymentProvider.label(_provider)} ».',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _holder,
                maxLength: 80,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText:
                      _provider == PaymentProvider.merchantCode
                          ? 'Nom du marchand'
                          : 'Nom du titulaire',
                  helperText: 'Montré au client pour qu’il vérifie à qui il envoie l’argent.',
                  counterText: '',
                ),
              ),
              if (_showsPhone) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  validator: _validatePhone,
                  decoration: InputDecoration(
                    labelText:
                        _provider == PaymentProvider.orangeMoney
                            ? 'Numéro Orange Money'
                            : _provider == PaymentProvider.mobileMoney
                            ? 'Numéro Mobile Money'
                            : 'Numéro',
                  ),
                ),
              ],
              if (_showsCode) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _code,
                  validator: _validateCode,
                  decoration: const InputDecoration(labelText: 'Code marchand'),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _ussd,
                keyboardType: TextInputType.text,
                validator: _validateUssd,
                decoration: const InputDecoration(
                  labelText: 'Code USSD « Payer maintenant » (facultatif)',
                  helperText:
                      'Dépend de votre opérateur : à définir vous-même. Vous pouvez utiliser '
                      '{numero}, {montant} et {code}.',
                  helperMaxLines: 3,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _instructions,
                maxLines: 5,
                maxLength: 1200,
                decoration: const InputDecoration(
                  labelText: 'Instructions (facultatif)',
                  helperText: 'Une étape par ligne. Vide : les étapes par défaut.',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _active,
                onChanged: (value) => setState(() => _active = value),
                title: const Text('Proposé à mes clients'),
                subtitle: const Text('Désactivé : caché sans être supprimé.'),
              ),
              const SizedBox(height: 8),
              Text('Logo (facultatif)', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (_newLogo != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        _newLogo!.bytes,
                        width: 56,
                        height: 56,
                        fit: BoxFit.contain,
                        errorBuilder:
                            (_, _, _) => const SizedBox(
                              width: 56,
                              height: 56,
                              child: Icon(Icons.broken_image_outlined),
                            ),
                      ),
                    )
                  else
                    PaymentOptionLogo(
                      optionId: option?.id,
                      provider: _provider,
                      hasLogo: hasCurrentLogo,
                      size: 56,
                    ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _pickLogo,
                          icon: const Icon(Icons.image_outlined),
                          label: const Text('Choisir un logo'),
                        ),
                        if (_newLogo != null || hasCurrentLogo)
                          TextButton(
                            onPressed:
                                () => setState(() {
                                  _newLogo = null;
                                  _removeLogo = option?.hasLogo ?? false;
                                }),
                            child: const Text('Retirer'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              PrimaryButton(label: 'Enregistrer', loading: _saving, onPressed: _save),
              if (_editing) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _saving ? null : _delete,
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  child: const Text('Supprimer ce moyen de paiement'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
