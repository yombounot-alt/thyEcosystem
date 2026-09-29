import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thy_design_system/thy_design_system.dart';
import 'package:thy_core/thy_core.dart';

import '../../../l10n/app_localizations.dart';
import '../application/auth_controller.dart';

class OtpVerifyScreen extends ConsumerStatefulWidget {
  const OtpVerifyScreen({super.key, required this.phone});

  final String phone;

  @override
  ConsumerState<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends ConsumerState<OtpVerifyScreen> {
  final _codeController = TextEditingController();
  bool _loading = false;
  bool _resending = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_codeController.text.trim().length != 6) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).otpNeedSixDigits)));
      return;
    }

    setState(() => _loading = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .verifyOtp(phone: widget.phone, code: _codeController.text.trim());
      // Navigation happens automatically via the router's redirect once auth state updates.
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      await ref.read(authControllerProvider.notifier).requestOtp(phone: widget.phone);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).otpResent)));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.otpTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t.otpSentTo(widget.phone), textAlign: TextAlign.center),
              const SizedBox(height: 32),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                style: const TextStyle(fontSize: 28, letterSpacing: 12),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(counterText: '', hintText: '••••••'),
              ),
              const SizedBox(height: 16),
              PrimaryButton(label: t.otpVerify, onPressed: _verify, loading: _loading),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _resending ? null : _resend,
                child: Text(_resending ? t.otpResending : t.otpResend),
              ),
              TextButton(onPressed: () => context.go('/phone'), child: Text(t.otpChangeNumber)),
            ],
          ),
        ),
      ),
    );
  }
}
